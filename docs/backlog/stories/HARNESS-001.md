---
id: HARNESS-001
title: Gate record tree stamp is verified end to end
slug: gate-record-tree-stamp-is-verified-end-t
epic: 
type: chore
status: in-review
phase: REVIEW
branch: story/HARNESS-001-gate-record-tree-stamp-is-verified-end-t
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

<!-- Why this story exists. Link the epic and any wiki pages that constrain it.
     Name the REQUIRED gate that would fail if this story's artifact broke. If
     only an optional gate can, put it in required_gates above before RED:
     every required gate once passed over a story none of them exercised. -->

Filed from `docs/wiki/audits/enforcement-mutants-2026-09-15.md`, cluster C1.

CLAUDE.md law 3 says "`## Gate results` ... carries the commit and a hash of the
code the gates ran against, and `check-boundaries.sh` refuses a PR where that
hash does not match the code being merged". Three mutants show that no test
observes any part of that sentence. All three survive the whole selftest (566
assertions, 13 suites):

1. `scripts/gates.sh:191` — `tree="$(gate_tree_hash)"` replaced by the constant
   `tree=0000000`. Every record the harness writes then carries a stamp that
   describes no tree at all.
2. `scripts/check-boundaries.sh:294` — `[ -n "$rec" ] && [ "$rec" = "$now" ]`
   replaced by `true`. The comparison that is supposed to refuse the PR accepts
   every stamp, including one for a different tree.
3. `.claude/hooks/lib.sh:637` — the tree hash stops covering `test` files, so a
   test edited after the last full gate run leaves the recorded hash matching.

The reason 2 survives is structural and applies to the whole of `check-boundaries.sh`:
`boundaries()` in `.claude/tests/boundaries.test.sh:23` captures the script's
output and never its exit status, and every assertion is an `assert_contains` on
a substring. A rule that stops firing is invisible unless some test constructs
the violating input and asserts on the refusal text. No test constructs a
stamp/tree mismatch.

**Required gate that would fail if this story's artifact broke - corrected at
PLANNED.** This line originally read: "`unit` (`bash scripts/selftest.sh` - the
harness's own suites)". That is wrong for this project twice over. `unit` is
`lune run test`, the Roblox suite; and no gate in `project.conf` runs
`selftest.sh` at all - the `harness` gate runs only
`.claude/tests/project-counters.test.sh`.

This story's artifact is an assertion in `.claude/tests/boundaries.test.sh`. What
fails if it breaks is the **`Harness self-test` step** at
`.github/workflows/gates.yml:108` (`bash scripts/selftest.sh`) - a required CI
step, not a gate. The consequence is concrete and must not be forgotten at
GATES: **`bash scripts/gates.sh` passes without ever running this story's
test.** `bash scripts/ci-local.sh` is what reproduces CI here.

`required_gates` stays empty deliberately - there is no repo-optional gate to
escalate that would cover a harness suite. Closing that hole is HARNESS-008's
territory, and HARNESS-008 is DONE having decided the fast loop carries
`project-counters` only, because `selftest.sh` runs 10-55 minutes on this
machine. This story does not reopen it.

## Prior verification: what the refresh already delivered

The audit that filed this story measured harness release **19**
(`VERSION 2026-09-15`, upstream commit `7b6f6db`). This repository has since
refreshed to release **30** (`8edf687`, `081b425`, `913ab09`, 2026-09-16), which
brought in upstream's own fix for C1. Line anchors were re-derived: the story
cites `check-boundaries.sh:294`, which is now **:371**; `gates.sh:191` and
`.claude/hooks/lib.sh:637` are unchanged.

A commit title is not evidence, so **every mutation the criteria name was run
against the shipped tree**, through `scripts/mutate.sh`, oracle
`bash scripts/selftest.sh boundaries`. Baseline: `boundaries: 73 passed, 0 failed`.

| AC | Mutation run | Result | Assertion that caught it |
|---|---|---|---|
| AC-1 | `s#\[ "$rec" = "$now" \]#true#` on `check-boundaries.sh` | `71 passed, 2 failed` | `a stamp describing a different tree is refused`, `a test changing alone breaks the stamp too` |
| AC-2 | `191s#tree="\$(gate_tree_hash)"#tree=0000000#` on `gates.sh` | `69 passed, 4 failed` | `and the stamp gates.sh wrote IS that hash` - expected `6d7be0334e84131aa6ed69d5d55cf37605da7084`, actual `0000000` |
| AC-3 | `s#'{ print "C#'$1 != "test" { print "C#` on `lib.sh` | `72 passed, 1 failed` | `a test changing alone breaks the stamp too` |
| AC-4 | `28s#; fail=1; }#; }#` on `check-boundaries.sh` | `45 passed, 28 failed` | 28 assertions, each reporting `said '...' but exited 0, so CI would merge this` |

All four restored byte-for-byte; `git diff` over `scripts/` and `.claude/hooks/`
empty, no `.bak` under `.claude/state/mutations/`.

**So AC-2, AC-3 and AC-4 are delivered and discriminating, and this story writes
nothing for them.** AC-4's probe is the sharpest of the four: it is the C3 defect
itself - a `check-boundaries.sh` that prints every correct word and refuses
nothing - and 28 assertions now see it.

### The one residual gap, which is what this story builds

AC-1 asks for a FAIL "naming the recorded tree **and the current one**". The
message does name both. Nothing pins the second half: the assertion's needle is
`gates were recorded against tree`, which floats, and matches a message that
named only the recorded tree.

Measured, not supposed - the fifth mutation:

```
$ bash scripts/mutate.sh scripts/check-boundaries.sh \
    's#but \$where is '\''\$now'\''\. ##' -- bash scripts/selftest.sh boundaries
  the gate record is a stamp on a tree, not a sentence about one

boundaries: 73 passed, 0 failed

1 harness suite(s) passed.
=== mutate: command exited 0; restored (verified byte-for-byte ...) ===
  374:         problem "story $sid: gates were recorded against tree '${rec:-none}' but $where is '$now'. ..."
```

Green, and byte-identical to baseline. Half of AC-1 is unobserved, which is the
"needle that cannot fail" failure in `rules.md` - the assertion has a sharp name,
runs, passes, and does not match what it claims. **PO decision (2026-09-17):**
AC-1 is not satisfied by behaviour that happens to be right; it asks for a test
that fails when either name is dropped. That test is this story's work.

## Acceptance criteria

<!-- Each AC is independently testable and phrased as observable behaviour.
     The Test Developer writes at least one failing test per AC.
     An AC that names a statistic, a metric or a threshold names a NEGATIVE
     CONTROL too: the deliberately broken input the metric must reject, and
     roughly what it should score. A criterion can be perfectly testable and
     still be blind to the defect it exists to catch, and that is more
     dangerous than a vague one - it survives review and goes green. -->

- **AC-1** — Given a story whose `## Gate results` was written by a real
  `gates.sh` run, when a source, test or config file changes afterwards and
  `check-boundaries.sh` runs, then it reports a FAIL naming the recorded tree
  and the current one. Kills: `scripts/check-boundaries.sh:294`
  `s#\[ "$rec" = "$now" \]#true#`.
- **AC-2** — Given the same story, when `gates.sh` records its result, then the
  `tree:` line it writes equals `gate_tree_hash` for that tree and is not a
  constant. Kills: `scripts/gates.sh:191`
  `s#tree="\$(gate_tree_hash)"#tree=0000000#`.
- **AC-3** — Given a recorded gate run, when only a **test** file changes
  afterwards, then the recorded tree hash no longer matches and
  `check-boundaries.sh` says so. Kills: `.claude/hooks/lib.sh:637`
  `s#'{ print "C#'$1 != "test" { print "C#`.
- **AC-4** — Given any invocation of `check-boundaries.sh` in the harness's own
  suite, when the script reports at least one FAIL, then the test observes a
  non-zero exit status. (The helper at `.claude/tests/boundaries.test.sh:23`
  currently discards it, which is why AC-1 has no test today.)

## Contract

**Nothing in production changes.** This story adds assertions to one existing
test file and nothing else. GREEN is expected to be a **no-op**, verified rather
than delegated. There is no signature change anywhere, so the "callers of every
changed signature" list is empty **by construction, not by omission**: no export,
no function and no script interface is touched.

### The file, and the block

`.claude/tests/boundaries.test.sh`, inside the existing
`describe "the gate record is a stamp on a tree, not a sentence about one"`
(opens at **:1160**; the source-moved case runs **:1195-1200**, the test-moved
case **:1205-1210**). Add to that block. Do not renumber, reword or reorder what
is there - AC-2, AC-3 and AC-4 are carried by those exact assertions and by
`refused`/`run_boundaries`, all four verified above.

### What must be pinned

The refusal `check-boundaries.sh` emits on a stamp/tree mismatch names **two**
hashes, and both are part of AC-1:

```
FAIL  story T-1: gates were recorded against tree '<RECORDED>' but the working
tree is '<CURRENT>'. Source, test or config changed after the last full gate
run; run 'bash scripts/gates.sh' again and commit the result.
```

* `<RECORDED>` - the `tree:` value `gates.sh` wrote into `## Gate results`
  **before** the change. Already pinned indirectly today.
* `<CURRENT>` - `gate_tree_hash` of the tree **after** the change. **Pinned by
  nothing.** This is the gap.

Both are 40-character lowercase hex (`git hash-object` output), and after the
mutation they differ. Assert on the **hash values themselves**, never on the
prose around them: a 40-char hex needle cannot be satisfied by a message that
means the opposite, which is the third defence in `rules.md`'s needle rule and
the only one that applies here.

### Helpers already in the file - use these, do not reimplement

| Helper | Line | Contract |
|---|---|---|
| `run_boundaries` | :32 | sets **`$out`** and **`$rc`**; returns nothing. Clears `GITHUB_HEAD_REF` and `PR_HEAD_SHA` |
| `refused <what> <needle>` | :41 | asserts `$out` contains `<needle>` **and** `$rc` is non-zero |
| `assert_contains <what> <needle> <haystack>` | `_lib.sh` | substring |
| `assert_eq <what> <expected> <actual>` | `_lib.sh` | equality |
| `story_blocked <phase> [required_gates]` | :236 | body on stdin; writes `project.conf`, commits, **runs the real `gates.sh`**, commits again |
| `commit_all [msg]` | :64 | stages and commits inside `$FIX` |

The fixture is `$FIX`; its story is `docs/backlog/stories/T-1.md` on branch
`story/T-1-fixture`.

Reading the two hashes, exactly as the block already does at :1188-1191:

```sh
rec_tree="$(sed -nE 's/^[[:space:]]*tree:[[:space:]]*([0-9a-f]+).*/\1/p' \
  "$FIX/docs/backlog/stories/T-1.md" | head -1)"
live_tree="$( cd "$FIX" && CLAUDE_PROJECT_DIR="$FIX" bash -c \
  '. .claude/hooks/lib.sh; gate_tree_hash' 2>/dev/null )"
```

**Order matters and is the one trap here.** `rec_tree` must be read **before**
the file is changed, `live_tree` **after** - otherwise both name the same tree
and the assertion is vacuous in the quietest possible way. A control that the
two differ (`assert_eq` would be wrong; assert they are NOT equal) is cheap and
worth having, because if they ever coincide every assertion below passes for the
wrong reason.

### Semantics of each number

* **40 hex characters** - `git hash-object --stdin` output, from
  `_hash_blob_listing`. Not a commit sha; it is a hash of a sorted
  `blob<TAB>path` listing over the gated set.
* **`'0000000'`** - the constant AC-2's mutant writes. Seven characters, so it
  is not a real hash and never collides with one.
* **`$where`** - the literal string `the working tree` locally, or
  `commit <7 chars>` when `PR_HEAD_SHA` is set. `run_boundaries` clears
  `PR_HEAD_SHA`, so **locally it is always `the working tree`.** The CI branch of
  that ternary (`check-boundaries.sh:367-372`) is not exercised by this suite -
  say so in the handoff rather than implying coverage this story does not add.

### Oracle partition

All **mechanical**. Nothing here is a threshold, a statistic or a matter of
taste: the expected values are two hashes the fixture can compute. Pin them
exactly; do not calibrate anything.

### Test-only dependencies

**None.** bash, git and coreutils, as every harness suite. Nothing is added to
any manifest, so RED's manifest allowance is not needed and must not be used.

### What earns the new assertion

The implementation is already correct, so the new assertion **passes on its
first run and every run after**. Under `rules.md` that is not a test yet. It is
earned by one mutation, already measured at PLANNED against today's tree:

```sh
bash scripts/mutate.sh scripts/check-boundaries.sh \
  's#but \$where is '\''\$now'\''\. ##' -- bash scripts/selftest.sh boundaries
```

Today that is `73 passed, 0 failed`. **With the new assertion in place it must go
red, and the red must be pasted into `## Regressions`** - message, counts and the
restore confirmation. `check-boundaries.sh` refuses a PR whose `## Regressions`
describes a failure without showing one, and a green run here would mean the new
needle is as blind as the old one.

### Cost, so it is planned for rather than discovered

`bash scripts/selftest.sh boundaries` is **~15 minutes** on this machine - it
runs the real `gates.sh` inside fixtures repeatedly. Budget two runs for RED (the
suite with the assertion added, then the earning mutation). Do not run the full
`selftest.sh`; it is 10-55 minutes and nothing here needs the other 17 suites.

## Deferred verifications

<!-- REQUIRED when a verification this story depends on provably cannot run in
     the phase that wants it; omit the section otherwise. Written by the Lead PO
     at PLANNED, and the phase that owns it pastes the result in.
     The case this exists for: a negative control for a round trip, a threshold
     or a codec has to break the real implementation to mean anything, and in
     RED there is no implementation to break. RED naming the control and saying
     it could not run it is the honest answer; RED claiming a verification it
     did not do is the failure. One block per entry:
       * what it verifies, as a falsifiable condition - "with one field dropped
         from the encoder, AC-1's property test MUST fail"
       * why the phase that wants it cannot run it
       * THE PHASE THAT OWNS IT, by name. check-boundaries.sh refuses a PR
         whose block names no phase
       * the RESULT, pasted, once that phase runs it: what was mutated, what
         failed, and that the file was restored - or the word WAIVED with the
         reason. check-boundaries.sh refuses a PR that has neither
     Schedule it into GATES rather than RED where you can: source is writable
     there, and a story that bounced back to RED mid-cycle gets its corrected
     assertions earned by the same mutation, for free. Do THREE mutations rather
     than one, and make one of them a wrong VALUE rather than a missing field: a
     suite that catches an omission can be blind to a corruption, and a codec
     that is uniformly wrong round-trips through itself perfectly. -->

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

Planned by `bash scripts/plan.sh write HARNESS-001` from `.claude/harness/models.conf`.
A PLAN, not a record: a session setting or an explicit override can beat both
this and the agent's own `model:` field, and nothing here can see which won.
The orchestrator still writes down the model each dispatch **resolved** to, by
name, below the table.

| Phase | Agent | Planned | Why |
|---|---|---|---|
| PLANNED | `lead-po` | `opus` | planning is the judgement phase: decomposition, the oracle partition, and what goes in the contract |
| RED | `test-developer` | `fable` | the measured case. With a partitioned contract to work from, the brief carries the judgement and the weaker model writes sharper negative controls than the stronger one did without it |
| GREEN | `feature-developer` | `opus` | the failure mode of a weaker model here is reaching green by weakening a test, which is the one thing this harness exists to prevent |
| GATES | `feature-developer` | `opus` | same risk as GREEN, and a gate failure is where "make it stop complaining" is most tempting |
| REVIEW | `lead-po` | `opus` | reading review feedback against the contract is judgement, and a wrong call here ships |
| SCAFFOLD | `lead-po` | `opus` | source, tests and config in one indivisible derivation, with no failing test in front of any of it |

**Resolved:**

**PO override of the rendered plan, at PLANNED: RED runs on `opus`, not `fable`.**

`plan.sh write` rendered `fable` for RED because a contract exists. It cannot
apply `models.conf`'s own `except | RED | unenforced | opus` row, because that
row turns on which **paths** the story writes and nothing in a story file tells
`plan.sh` what those are. Asked directly:

```
$ bash scripts/classify.sh .claude/tests/boundaries.test.sh
harness	.claude/tests/boundaries.test.sh
```

`harness`, not `test` - and harness is writable in **every** phase. So the phase
lock freezes nothing this story touches. RED here could write
`scripts/check-boundaries.sh` and the guard would allow it. That is precisely the
exception's stated condition, "the lock freezes none of the paths this story
names, so the contract is not an aid to the model here - it is the only
enforcement there is", and its reasoning applies unchanged.

The consequence is larger than a model choice and belongs in every brief for
this story: **the only thing keeping RED off production source is the brief and
the review.** A test-only story whose test file the lock will not protect is the
one shape where "never edit production in RED" is a convention rather than a
control.

**Success condition, falsifiable either way:** RED returns an assertion that (a)
pins both hashes by value, and (b) goes red under the earning mutation recorded
in the Contract, with no edit to any file outside
`.claude/tests/boundaries.test.sh`. If it edits production source, or returns an
assertion the mutation leaves green, the override was wrong and the verdict says
so.

| Phase | Agent | Planned | RESOLVED | Note |
|---|---|---|---|---|
| PLANNED | `lead-po` | `opus` | **`claude-opus-5`** (this session, per the environment's stated model id) | as planned |
| RED | `test-developer` | `fable` | **`opus`**, passed explicitly to the Agent tool | overridden per the `unenforced` row above |

## Out of scope

* **Rewriting or reordering the existing assertions** in the
  `the gate record is a stamp on a tree` block. AC-2, AC-3 and AC-4 are carried
  by them and all four were verified by mutation at PLANNED. Touching them risks
  the coverage this story is here to complete.
* **The `PR_HEAD_SHA` branch** of `check-boundaries.sh:367-372`. The audit says
  plainly it had no measurement of it, and `run_boundaries` clears the variable.
  Covering CI's own code path needs a different fixture and is its own story.
* **Making a local gate run cover the harness suites.** Named in Context and left
  there: `gates.sh` will pass without running this story's test, and that is
  HARNESS-008's decided trade-off, not a defect to fix here.
* **Any change to `scripts/check-boundaries.sh`, `scripts/gates.sh` or
  `.claude/hooks/lib.sh`.** All three are correct. This story adds a test.
* **Re-auditing clusters C2 and beyond.** HARNESS-002 owns C2.
## Design notes

<!-- Filled by the Lead Designer for user-facing stories: layout, states,
     tokens, accessibility requirements. Omit for non-UI stories. -->

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

**Level.** One level only: the harness's own shell suite,
`.claude/tests/boundaries.test.sh`, run by `bash scripts/selftest.sh boundaries`.
That is where the contract lives - `check-boundaries.sh` is a script whose
observable behaviour is its stdout and its exit status, and the existing fixture
already builds a real two-branch repository with a real `gates.sh` record in it.
Nothing cheaper can falsify AC-1, and nothing more expensive is needed.

**Files touched:** `.claude/tests/boundaries.test.sh` only. No production file,
no config, no manifest. Verified with `git status --porcelain`.

**Where.** Inside the existing
`describe "the gate record is a stamp on a tree, not a sentence about one"`
(opens at :1160). Every pre-existing line in that block is byte-identical; the
diff is **insertions only** (`diff` shows `1193a…`, `1198a…`, `1200a…`,
`1206a…`, `1208a…`, `1210a…` against the old file and no `c` or `d` hunk). AC-2,
AC-3 and AC-4 are carried by those untouched lines.

**Three helpers, added immediately above the two cases they serve:**

| Helper | What it is for |
|---|---|
| `fix_tree_hash` | `gate_tree_hash` of `$FIX`, computed exactly as the existing :1190 does. Used to read the live tree *after* each change. |
| `rec_tree_of_fixture` | the `tree:` stamp out of the fixture story, read exactly as the existing :1188 does. Needed because the test-only case runs a **second** `gates.sh`, so `$rec_tree` from :1188 is stale there. |
| `assert_sha40 <what> <value>` | the shape guard. Every new needle is a **variable**, and the empty string is a substring of every haystack - an unread hash would make both `refused` calls pass while asserting nothing. |
| `assert_differ <what> <a> <b>` | the control demanded by the Contract. `assert_eq` would be the wrong direction; this fails, and prints the shared value, if the two hashes ever name the same tree. |

**The assertions, and the AC each covers.** All ten are new; the two `refused`
lines already in the block are untouched.

*Case A - source moved after the gate run (`:1244-1257`).* `$rec_tree` is the
value read at **:1188, before** the two writes at :1244-1245; `now_tree` is read
at **:1249, after** them and after `commit_all`, and before `run_boundaries`.

| Assertion | Covers | Claim |
|---|---|---|
| `the recorded tree is a real hash, not an empty read` | AC-1 (guard) | `$rec_tree` is 40 lowercase hex, so the needle below is not the empty string |
| `the tree after the source change is a real hash too` | AC-1 (guard) | same for `$now_tree` |
| `control: source moved, so the two hashes name different trees` | AC-1 (control) | the two hashes differ. If they ever coincided there would be no mismatch to refuse and every assertion here would pass for the wrong reason |
| `the refusal names the RECORDED tree by value` | AC-1, AC-4 | `$out` contains the 40-char recorded hash **and** `$rc` is non-zero (`refused` asserts both) |
| `and the CURRENT tree by value - the half nothing pinned` | **AC-1, the gap** | `$out` contains the 40-char post-change hash. This is the assertion the earning mutation kills |

*Case B - a test file moved alone (`:1259-1277`).* `rec_tree_t` is read at
:1266, after the second `story_blocked REVIEW` wrote a fresh record and
**before** the test file is rewritten; `now_tree_t` at :1269, after.

| Assertion | Covers | Claim |
|---|---|---|
| `the record from the second run is a real hash` | AC-3 (guard) | shape of `rec_tree_t` |
| `and the tree after the test-only change is too` | AC-3 (guard) | shape of `now_tree_t` |
| `control: a test moving alone still changes the tree hash` | AC-3 (control) | the gated set really does cover `test`, asserted on the hashes rather than on the refusal prose - this is `lib.sh:637`'s mutant seen from the other side |
| `the test-only refusal names the RECORDED tree by value` | AC-1, AC-3, AC-4 | as above, for the test-only path |
| `and the CURRENT tree by value, for a test-only change` | **AC-1, the gap**, AC-3 | as above |

**Why by value and not by prose.** `rules.md` offers three defences for a
needle. Anchoring the match and picking a needle whose negation is not also a
match are both properties of *prose*, and neither helps here: the message is one
long sentence and the defect is a **missing clause**, not a wrong word. A
40-character hex string is the third defence - no message meaning the opposite
can produce one - and it is the only one that applies.

**Not covered, deliberately.** The `PR_HEAD_SHA` branch of
`check-boundaries.sh:367-372` (`where` = `commit <7 chars>`). `run_boundaries`
clears `PR_HEAD_SHA`, so `$where` is always `the working tree` here. Out of
scope per the story, and the new assertions do not imply coverage of it.

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

**GREEN IS EXPECTED TO BE A NO-OP.** This story adds assertions to one existing
test file and changes no production file. There is nothing to implement: the
behaviour AC-1 names is already correct in `scripts/check-boundaries.sh`, which
is why the new assertions pass on arrival. GREEN's job is to verify that claim -
that the source is untouched and still passes - and to record it, not to write
code. If GREEN finds itself editing `scripts/check-boundaries.sh`,
`scripts/gates.sh` or `.claude/hooks/lib.sh`, something has gone wrong; all
three are in `## Out of scope`.

### The exact command

```
bash scripts/selftest.sh boundaries
```

Add `VERBOSE=1` in front to see the `ok` lines as well as the failures. It takes
**about 15 minutes** on this machine: the fixture runs the real `gates.sh`
inside itself, twice inside this block alone.

**`bash scripts/gates.sh` does NOT run this suite, and neither does
`--fast`.** No gate in `project.conf` invokes `selftest.sh`; the `harness` gate
runs `.claude/tests/project-counters.test.sh` only. What runs this story's test
is the **`Harness self-test` step** in `.github/workflows/gates.yml:108`
(`bash scripts/selftest.sh`), a required CI step. Locally the equivalent is
`bash scripts/ci-local.sh`. Do not read a green `gates.sh` as evidence about
this story - it never looked.

### State on arrival: PASSING, and why that is expected

```
boundaries: 83 passed, 0 failed
```

73 before this story, 83 after: ten new assertions, all green on their first
execution. That is not an omission and not a mistake. The implementation exists
and is right - the defect this story fixes is in the **test**, which named one
of the two hashes with a floating prose needle and so could not tell a correct
message from one that had lost half its content.

So "watch it fail" is discharged the other way, by the mutation in
**`## Regressions`**: the clause naming the current tree was deleted from the
refusal at `scripts/check-boundaries.sh:374` through `scripts/mutate.sh`, and the
suite went to `81 passed, 2 failed` - the two failures being precisely the two
new assertions that name the CURRENT tree, with every other assertion in the
file, including the eight other new ones, still green. Before this story the
same mutation left the suite at `73 passed, 0 failed`. The output, the counts
and the byte-for-byte restore confirmation are pasted there.

Note also that the suite here does **not** fail at import: it is a shell script
that runs top to bottom, so every new assertion and both controls genuinely
executed. The usual RED caveat - "the controls are claims until GREEN measures
them" - does not apply. The numbers below were measured, not predicted.

### Files touched

| File | Change |
|---|---|
| `.claude/tests/boundaries.test.sh` | insertions only, inside the existing `describe "the gate record is a stamp on a tree, not a sentence about one"`. Three helpers, ten assertions, two hash reads. |
| `docs/backlog/stories/HARNESS-001.md` | `## Test plan`, `## Handoff: RED -> GREEN`, `## Regressions`. |

Nothing else. `git status --porcelain` shows those two paths and no others, and
`git diff --stat scripts/ .claude/hooks/` is empty.

### What the tests pin - the "export shape", for a shell suite

There is no module and no signature here, so the equivalent contract is the
**observable interface of `scripts/check-boundaries.sh`**, and these assertions
now hold it fixed:

1. On a stamp/tree mismatch the script writes to **stdout** (captured with
   `2>&1`) a line containing **both** 40-character lowercase hex hashes: the
   `tree:` value recorded in `## Gate results`, and `gate_tree_hash` of the tree
   as it stands now. Substrings, not a format - the surrounding prose,
   punctuation and line breaks are **not** constrained, and may be reworded
   freely. What may not happen is either hash disappearing.
2. The same run exits **non-zero** (`refused` asserts output and status
   together, which is AC-4).
3. `gate_tree_hash` covers `test` files: a commit that moves only
   `tests/main.test.ts` changes the hash (AC-3), asserted on the hash values
   themselves and not only on the refusal text.
4. The `tree:` line stays greppable as
   `^[[:space:]]*tree:[[:space:]]*([0-9a-f]+)` in `## Gate results`, and its
   value is 40 lowercase hex - `gate_tree_hash`'s own output, never a
   placeholder.

**Not constrained, deliberately:** the wording of the refusal; the order of the
two hashes within it; whether they are quoted; the `PR_HEAD_SHA` branch at
`check-boundaries.sh:367-372`, where the location becomes `commit <7 chars>`
(`run_boundaries` clears the variable, so this suite never reaches it - saying so
here rather than implying coverage this story does not add).

### Negative controls: expected values, and the values measured

Both controls ran. `assert_differ` fails, loudly and naming the shared value, if
the two hashes it is given are equal.

| Control | Expected | Measured in the run above |
|---|---|---|
| `control: source moved, so the two hashes name different trees` | two distinct 40-hex hashes | recorded `89e98fee9d0616e17589f86fbd7e793d88c8ea24`, current `f443c354d85da58ba1359317d1d0102f7355d679` - **differ** |
| `control: a test moving alone still changes the tree hash` | two distinct 40-hex hashes | recorded `89e98fee9d0616e17589f86fbd7e793d88c8ea24`, current `9e45d5ea7a1475f68bb1260fab217ff6848957f2` - **differ** |
| `assert_sha40`, four calls | `40 lowercase hex` for every needle | all four `40 lowercase hex` |

**These hashes are NOT hard-coded anywhere in the test, and must not be.** They
are recorded here as the values this run observed, for comparison if the suite
ever behaves oddly. `make_project_fixture` copies the *real* `paths.conf`,
`phases.conf`, `models.conf` and `VERSION` into the fixture, so the fixture's
tree hash changes whenever any of those change. A test that embedded these
constants would fail on the next harness refresh for no reason; the assertions
compute them instead, which is why `assert_sha40` and `assert_differ` exist -
they are what stops a *computed* needle from silently becoming the empty string.

Worth knowing: the recorded hash is the same in both cases
(`89e98fee...`). `story_blocked` resets to `main` and rewrites identical content,
so the second `gates.sh` run legitimately stamps the same tree. The two
*current* hashes differ from it and from each other, which is what the
assertions turn on.

### Discovered, and worth carrying forward

* The floating-needle defect is structural, not local. `assert_contains` over a
  prose fragment is the dominant idiom in this suite, and every one of them can
  be satisfied by a message that lost the half the assertion's name claims to
  care about. This story fixes the one instance AC-1 names. A sweep is a
  different story.
* The mutated message reads `...against tree '89e98fee...' Source, test or
  config changed...` - two sentences fused with no separator. Grammatically
  broken and still invisible to every prose needle in the file. That is the case
  for asserting on values.

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

**This story did not return from GREEN or GATES.** The section is here for the
other reason `rules.md` gives it: an assertion written while the implementation
already exists has never been observed to fail, and is earned by a deliberate,
reverted mutation of the specific production behaviour it claims to pin.

**Which assertion, and what was wrong with the old one.** AC-1 asks for a FAIL
naming the recorded tree **and the current one**. The only assertion covering it
was `refused "a stamp describing a different tree is refused" "gates were
recorded against tree"` - a needle that floats and that a message naming only the
*recorded* tree satisfies exactly as well. Half of AC-1 was unobserved.

**What it asserts now.** Both hashes by value: `refused ... "$rec_tree"` and
`refused ... "$now_tree"`, in the source-moved case and again in the test-only
case, with `assert_sha40` guarding each needle against being the empty string and
`assert_differ` controlling that the two hashes really do name different trees.

**What earns it.** One mutation, through `scripts/mutate.sh` - which restores the
file and verifies the restore - deleting the clause that names the current tree.
The command is the one recorded in the Contract, run verbatim; its output
follows.

```
=== mutate: scripts/check-boundaries.sh (1 line(s) changed by s#but \$where is '\$now'\. ##) ===
  374 -         problem "story $sid: gates were recorded against tree '${rec:-none}' but $where is '$now'. Source, test or config changed after the last full gate run; run 'bash scripts/gates.sh' again and commit the result."
  374 +         problem "story $sid: gates were recorded against tree '${rec:-none}' Source, test or config changed after the last full gate run; run 'bash scripts/gates.sh' again and commit the result."

=== mutate: running bash scripts/selftest.sh boundaries ===

  the gate record is a stamp on a tree, not a sentence about one
    FAIL and the CURRENT tree by value - the half nothing pinned
         expected a refusal saying: f443c354d85da58ba1359317d1d0102f7355d679
         actual:                    ok    story files validated
         ok    harness state not tracked
         ok    source changes accompanied by test changes (1 source, 1 test)
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         ok    recorded gate result: blocked (1 required gate(s) could not run; 2 ran, 0 unconfigured, 0 known)
         ok    blocked gate 'types' is recorded as pending CI
         FAIL  story T-1: gates were recorded against tree '89e98fee9d0616e17589f86fbd7e793d88c8ea24' Source, test or config changed after the last full gate run; run 'bash scripts/gates.sh' again and commit the result.
         ok    ## Handoff is filled in
    FAIL and the CURRENT tree by value, for a test-only change
         expected a refusal saying: 9e45d5ea7a1475f68bb1260fab217ff6848957f2
         actual:                    ok    story files validated
         ok    harness state not tracked
         ok    source changes accompanied by test changes (0 source, 1 test)
         ok    story T-1 is in REVIEW
         ok    branch matches the story's frontmatter
         ok    acceptance criteria unchanged since main
         ok    recorded gate result: blocked (1 required gate(s) could not run; 2 ran, 0 unconfigured, 0 known)
         ok    blocked gate 'types' is recorded as pending CI
         FAIL  story T-1: gates were recorded against tree '89e98fee9d0616e17589f86fbd7e793d88c8ea24' Source, test or config changed after the last full gate run; run 'bash scripts/gates.sh' again and commit the result.
         ok    ## Handoff is filled in

boundaries: 81 passed, 2 failed

1 of 1 harness suite(s) FAILED.

=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/scripts_check-boundaries.sh.20260918T040343Z.1186841.bak) ===
  374:         problem "story $sid: gates were recorded against tree '${rec:-none}' but $where is '$now'. Source, test or config changed after the last full gate run; run 'bash scripts/gates.sh' again and commit the result."
```

**Why this is the right red.** The two failures are exactly the two assertions
that name the CURRENT tree. Everything else stayed green, including the two that
name the RECORDED tree - the clause deleted is the one carrying the second hash
and no other. And the mutated message still contains
`gates were recorded against tree`, so the pre-existing needle is *still
satisfied* by it: the old assertions pass throughout this run. That is the defect
being demonstrated, not an artefact of it.

**Before and after, on the same mutation:**

| Tree | Same mutation, same oracle | Result |
|---|---|---|
| before this story, 73 assertions | `bash scripts/selftest.sh boundaries` | `73 passed, 0 failed` - byte-identical to baseline, the mutant survives |
| after this story, 83 assertions | same | `81 passed, 2 failed` - the mutant is dead |

**Restored.** `mutate.sh` verified the restore byte-for-byte and printed line 374
back; `git status --porcelain` afterwards shows only
`.claude/tests/boundaries.test.sh` and `docs/backlog/stories/HARNESS-001.md`,
`git diff --stat scripts/ .claude/hooks/` is empty, and
`.claude/state/mutations/` holds only `log` - no `.bak` left behind.

**The clean run, for the record** - the same suite with the new assertions in
place and no mutation:

```
  the gate record is a stamp on a tree, not a sentence about one
    ok   a record made against this tree matches it
    ok   and the stamp gates.sh wrote IS that hash
    ok   a stamp describing a different tree is refused
    ok   the recorded tree is a real hash, not an empty read
    ok   the tree after the source change is a real hash too
    ok   control: source moved, so the two hashes name different trees
    ok   the refusal names the RECORDED tree by value
    ok   and the CURRENT tree by value - the half nothing pinned
    ok   a test changing alone breaks the stamp too
    ok   the record from the second run is a real hash
    ok   and the tree after the test-only change is too
    ok   control: a test moving alone still changes the tree hash
    ok   the test-only refusal names the RECORDED tree by value
    ok   and the CURRENT tree by value, for a test-only change

boundaries: 83 passed, 0 failed

1 harness suite(s) passed.
```

### GREEN was a no-op, verified rather than delegated

No `feature-developer` was dispatched. The handoff predicted a no-op - the
behaviour AC-1 names is already correct - and dispatching an implementer with
nothing to implement is how a story acquires a change it did not need. The
orchestrator verified it directly instead.

**The source was untouched.** The whole branch, against `main`:

```
$ git diff --stat main...HEAD
 .claude/tests/boundaries.test.sh    |  67 ++++
 docs/backlog/stories/HARNESS-001.md | 613 +++++++++++++++++++++++++++++++-----
 2 files changed, 625 insertions(+), 55 deletions(-)

$ git diff main...HEAD -- scripts .claude/hooks .claude/harness src lune default.project.json
                                         (no output)

$ git diff --name-only main...HEAD | while read -r f; do bash scripts/classify.sh "$f"; done
harness	.claude/tests/boundaries.test.sh
docs	docs/backlog/stories/HARNESS-001.md
```

Two paths, one `harness` and one `docs`. No source, no config, no manifest, in
any commit on this branch.

**And it still passes**, unmutated, on the committed tree:

```
$ bash scripts/selftest.sh boundaries

  the gate record is a stamp on a tree, not a sentence about one

  production code arrives with tests, or with an inventory

boundaries: 83 passed, 0 failed

1 harness suite(s) passed.
```

**The negative controls were confirmed, not assumed.** `rules.md` warns that in
an ordinary RED the suite fails at import, so its controls are claims until GREEN
measures them. That does not apply to a shell suite, which runs top to bottom -
but the confirmation is cheap and the failure mode it guards against is silent,
so it was done anyway. In the orchestrator's own mutation run the two
`assert_differ` controls and all four `assert_sha40` guards were among the 81
assertions that stayed **green** while only the two CURRENT-tree assertions went
red. Values measured, matching RED's table exactly:

| Control | Expected | Measured, independently |
|---|---|---|
| `control: source moved, ...` | two distinct 40-hex hashes | `89e98fee9d0616e17589f86fbd7e793d88c8ea24` vs `f443c354d85da58ba1359317d1d0102f7355d679` - differ |
| `control: a test moving alone ...` | two distinct 40-hex hashes | `89e98fee9d0616e17589f86fbd7e793d88c8ea24` vs `9e45d5ea7a1475f68bb1260fab217ff6848957f2` - differ |
| `assert_sha40` x4 | `40 lowercase hex` | all four `40 lowercase hex` |

**The mutation table was reproduced, not taken on trust.** RED reported
`81 passed, 2 failed` under the earning mutation. The orchestrator ran the same
`scripts/mutate.sh` invocation itself and got the same counts, the same two
failing assertions and the same three hashes, with the restore verified
byte-for-byte a second time (backup
`scripts_check-boundaries.sh.20260918T042723Z.1235334.bak`, distinct from RED's).

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-18T05:14:07Z
    commit: 6f2169c
    tree:   1ac80a2930c7e063aff67c8d6a02c4575daf8998
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 43)
    PASS         lint (2s, observed 43, floor 1)
    PASS         typecheck (5s, observed 8)
    PASS         unit (44s, observed 197, floor 197)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (1s, observed 25103)
    PASS         harness (32s, observed 40)
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

