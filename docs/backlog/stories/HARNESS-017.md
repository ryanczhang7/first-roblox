---
id: HARNESS-017
title: plan.sh write adds a missing Model guidance section
slug: plan-sh-write-adds-a-missing-model-guida
epic: 
type: fix
status: in-review
phase: REVIEW
branch: story/HARNESS-017-plan-sh-write-adds-a-missing-model-guida
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

<!-- Why this story exists. Link the epic and any wiki pages that constrain it.
     Name the REQUIRED gate that would fail if this story's artifact broke. If
     only an optional gate can, put it in required_gates above before RED:
     every required gate once passed over a story none of them exercised. -->

`bash scripts/plan.sh write <id>` (`cmd_write` in `scripts/plan.sh`) renders the
plan into a scratch file and splices it in with an awk that fires only on
`/^## Model guidance/`. A story with no such heading passes through that awk
unchanged, and the command still prints `wrote the model plan into ...` and exits
0. Observed on 2026-09-28 with HARNESS-016, which was filed by hand: the command
reported success, the file had no plan, and nothing said so until a heading was
added by hand and the command re-run.

The fix **inserts** the section rather than refusing. `rules.md` makes the plan
a fact of every story ("`plan.sh write <id>` renders it into the story's
`## Model guidance` at the end of PLANNED"). A refusal whose only remedy is
"type the heading and run again" is a manual step the tool can do itself, and
it can put the heading in the template's order, which a hand edit often gets
wrong. The success line then has to be true.

Required gate that fails if this breaks: `harness`. It runs
`.claude/tests/plan.test.sh`.

## Acceptance criteria

<!-- Each AC is independently testable and phrased as observable behaviour.
     The Test Developer writes at least one failing test per AC.
     An AC that names a statistic, a metric or a threshold names a NEGATIVE
     CONTROL too: the deliberately broken input the metric must reject, and
     roughly what it should score. A criterion can be perfectly testable and
     still be blind to the defect it exists to catch, and that is more
     dangerous than a vague one - it survives review and goes green. -->

- **AC-1** — Given a story file with no `## Model guidance` heading, when
  `plan.sh write <id>` runs, then it exits 0 and the file afterwards has exactly
  one `## Model guidance` heading. That section's body carries the generated
  region, with its `| RED |` row. The command's output also says that the
  section was added. *Control:* today's `cmd_write` leaves the file with zero
  such headings and prints only `wrote the model plan`, so it fails every clause.
- **AC-2** — The inserted section goes where `scripts/new-story.sh`'s template
  puts it: immediately before the first heading of a section the template places
  **after** `## Model guidance` (`Out of scope`, `Design notes`, `Test plan`,
  `Handoff: RED -> GREEN`, `Regressions`, `Gate results`, `Gate probes`,
  `Scaffold inventory`, `Notes`). If the story has none of those, it goes at the
  end of the file. *Control:* an implementation that always appends at the end
  fails the case whose story has `## Out of scope` and `## Notes`.
- **AC-3** — Inserting the section changes nothing else in the file. Every line
  of the original story is still present, in its original order, and the
  existing `plan.test.sh` cases for stories that already have the heading still
  pass. *Control:* an insertion that replaces the following heading, rather than
  going in front of it, loses `## Out of scope` and fails.

## Contract

<!-- Written by the Lead PO BEFORE RED, and AMENDABLE BY RED IN PLACE with a
     reason - GREEN then builds what the amended block says. This is where "RED
     tested one shape and GREEN built another" is prevented, and it is not the
     acceptance criteria: the criteria are frozen and change only through
     ## Amendments; this is a working agreement RED is expected to sharpen.
     One block per thing the story touches:
       * module paths and exported names, exactly
       * exact signatures, and the types the assertions will destructure
       * THE SEMANTICS BEHIND EACH NUMBER - not clamp(latitude) but "latitude
         clamps at +/-85, and dragging DOWN brings the north into view". One
         sentence per number settles a sign error in one line
       * the accessible markup for anything user-facing: roles, labels, what is
         a sibling of what
       * the oracle partition of the criteria (settled / oracle-free /
         mechanical - see story-authoring)
       * baseline measurements the story may read out rather than re-derive,
         each with what it was measured on
       * TEST-ONLY DEPENDENCIES this story is likely to need, by name. RED
         may add them itself, but only inside the dev block - so a library
         production will ALSO use is a GREEN change and is better decided
         here than discovered mid-phase. Where the ecosystem has no dev
         block at all (go.mod, requirements.txt, *.csproj), RED cannot
         declare one and the phase round trip is yours to plan for
       * FOR EVERY EXISTING EXPORT WHOSE SIGNATURE THIS STORY CHANGES: every
         caller, source and test, grep-listed here before dispatch. RED cannot
         find these itself - the old signature still exists during RED, so a
         caller of it still compiles and is absent from RED's typecheck. One
         such file went missing and took 25 tests with it, silently, at GREEN. -->

**Files.** `scripts/plan.sh` (`cmd_write`) and `.claude/tests/plan.test.sh`.
Both classify as `harness`, so the phase lock permits writing either one in any
phase. The only thing enforcing RED-before-GREEN here is this contract. RED
writes only the test file, and GREEN writes only `scripts/plan.sh`.

**No signature changes.** `bash scripts/plan.sh write <id>` keeps its arguments. The only
new output is one extra stdout line, and only when the section was absent. It
says `added a ## Model guidance section` (exact wording is GREEN's choice, but
it must contain `added` and `Model guidance`). `.claude/tests/plan.test.sh` sends
`plan write` to `/dev/null` everywhere else, so no existing needle reads stdout.

**Insertion point.** If `^## Model guidance` is absent, the section goes before
the first line matching `^## (Out of scope|Design notes|Test plan|Handoff|Regressions|Gate results|Gate probes|Scaffold inventory|Notes)`,
or at EOF if no line matches. The list is the template order in
`scripts/new-story.sh`. A comment next to it names that file, so a new template
section is visibly a two-place change. Section names are matched as prefixes
(`Handoff` covers `Handoff: RED -> GREEN`).

**Oracle partition.** All three ACs are *mechanical*: pin exact headings and
counts, and leave nothing open-ended.

**Tooling.** Bash, awk and coreutils only (`.claude/harness/rules.md`, Portability). There are
no test dependencies.

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
       * THE PHASE THAT OWNS IT, declared as `Owner: GATES` (or RED, GREEN,
         REVIEW). check-boundaries.sh refuses a PR
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

**DV-1: AC-3's "nothing else moved" assertions, earned by a mutation.** Three
AC-3 assertions pass in RED: `and nothing else in the file moved`,
`still touching nothing else` and `and the story above it intact`. They pass
only because nothing is inserted, so cutting a section that does not exist
returns the original file. After GREEN, they **must** fail against an insertion
that replaces the heading it goes in front of (it prints the plan *instead of*
`## Out of scope` rather than before it). RED cannot run this: there is no
insertion to mutate. **Owner: GATES.**

**Result (GATES, 2026-09-29).** Three mutations were run through
`bash scripts/mutate.sh scripts/plan.sh '<expr>' -- bash .claude/tests/plan.test.sh`.
Every restore was verified byte for byte. Each mutation covers a different
code path, plus the one pass-on-arrival assertion AC-1 has:

1. The insertion **replaces** the heading it should go in front of (DV-1 as
   written): `{ plan() }` → `{ plan(); next }` on the later-sections rule.
   ```
       FAIL it goes immediately before Out of scope
       FAIL and nothing else in the file moved
       FAIL before whichever later section comes first
       FAIL still touching nothing else
   plan: 94 passed, 4 failed
   === mutate: command exited 1; restored (verified byte-for-byte against .../scripts_plan.sh.20260929T000508Z.127175.bak) ===
   ```
2. The end-of-file path writes something that does not belong. This covers
   T-62, which mutation 1 cannot reach:
   `if (last !~ /^[[:space:]]*$/) print ""` → `print "stray line"`.
   ```
       FAIL and the story above it intact
   plan: 97 passed, 1 failed
   === mutate: command exited 1; restored (verified byte-for-byte against .../scripts_plan.sh.20260929T000809Z.137668.bak) ===
   ```
3. Refuse rather than insert: `|| added=1` → `|| die "no Model guidance heading"`.
   This earns `a story without the heading is written, not refused`, which
   passed in RED only because the bug also exits 0.
   ```
       FAIL a story without the heading is written, not refused
       FAIL and afterwards has exactly one Model guidance heading
       ... (9 more, every AC-1/AC-2 assertion)
   plan: 87 passed, 11 failed
   === mutate: command exited 1; restored (verified byte-for-byte against .../scripts_plan.sh.20260929T001057Z.148061.bak) ===
   ```

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

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write HARNESS-017` from `.claude/harness/models.conf`.
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

Lock coverage: APPLIES — all 4 path(s) scanned from the Contract text are harness/docs/ignored, so RED stays on the stronger model.
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

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

- PLANNED: `lead-po` role, run inline by the orchestrating session on
  `claude-opus-5-5`. No subagent was dispatched.
- RED: run inline by the orchestrating session on `claude-opus-5-5`, which
  matches the plan's `opus`. No subagent was dispatched.
- GREEN, GATES: run inline by the orchestrating session on `claude-opus-5-5`,
  which matches the plan's `opus`. No subagent was dispatched.

## Out of scope

<!-- Explicit non-goals. Prevents the Feature Developer from over-building. -->

- `^## Model guidance` also matches a heading such as `## Model guidance notes`.
  This is a pre-existing looseness, and it is not changed here.
- Headings inside fenced code blocks are not special-cased.
- Other generated sections (`## Gate results`) are not audited for the same
  defect here. If one of them has it, that is its own story.

## Design notes

<!-- Filled by the Lead Designer for user-facing stories: layout, states,
     tokens, accessibility requirements. Omit for non-UI stories. -->

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

All the tests are in `.claude/tests/plan.test.sh`, under
`describe "a story with no Model guidance heading gets one"`, at the end of the
file. Fixtures are built by `bare_story <id> <heading>...`, a story with
Context, criteria and a contract but no `## Model guidance`.

| Fixture | Later headings | Assertions | AC |
|---|---|---|---|
| T-60 | Out of scope, Notes | exit 0; exactly one `## Model guidance` (`grep -cx`); body has `GEN_BEGIN` and `\| RED \|`; one stdout line matching `added.*Model guidance` | AC-1 |
| T-60 | ″ | heading list is `… Contract, Model guidance, Out of scope, Notes` | AC-2 |
| T-60 | ″ | cutting the section out again returns the original file byte for byte | AC-3 |
| T-61 | Test plan, Out of scope, Handoff: RED -> GREEN | goes before `Test plan`, the first later section, not before `Out of scope`; original intact | AC-2, AC-3 |
| T-62 | none | goes last; carries the plan; original intact | AC-2, AC-3 |
| T-60 again | — | a second write leaves one heading and one `\| RED \|` row | AC-1 |

AC-3's second clause says the existing write cases still pass. That is every
earlier `plan write` case in the file, and none of them was edited.

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

**Command.** `bash .claude/tests/plan.test.sh`. It takes about 2m40s on this
Windows machine.

**RED output** (the `FAIL` lines and the verdict, against `scripts/plan.sh` at
`e82464b`):

```
    FAIL and afterwards has exactly one Model guidance heading
    FAIL whose body is the generated region
    FAIL with the plan in it
    FAIL and the command says it added the section
    FAIL it goes immediately before Out of scope
    FAIL before whichever later section comes first
    FAIL at the end when no later section exists
    FAIL with the plan in it there too
    FAIL a second write does not add a second section
    FAIL nor a second table
plan: 88 passed, 10 failed
```

**Why it is the right failure.** Each failing heading list comes back as the
original list with no `## Model guidance` in it (for example
`actual: ## Context / ## Acceptance criteria / ## Contract / ## Out of scope / ## Notes`).
That is the reported defect: the splice awk passes the file through unchanged.
None of the earlier 84 assertions fails.

**Passed on arrival**, and what earns each one:
- `a story without the heading is written, not refused` (exit 0) passes because
  today's bug also exits 0. It is earned by the contract's choice to insert
  rather than refuse. A `die` on a missing heading would turn it red.
- The three AC-3 "original intact" assertions pass vacuously while nothing is
  inserted. They are earned by DV-1 in GATES.

**What the tests pin, and what they leave free.**
- *Pinned:* the heading order; exactly one `## Model guidance` line
  (`grep -cx`, so the heading is exactly that text with nothing after it); the
  generated region inside the section; byte-identity of everything outside the
  section; and a stdout line containing `added` followed by `Model guidance`.
- *Left free:* the exact wording of that line; the blank lines inside the new
  section; and how the "later sections" list is expressed in `scripts/plan.sh`,
  as long as it follows the template order in `## Contract`.

**One constraint on the implementation.** `without_guidance` cuts from the
heading to the line before the next `## `. So the inserted block must end
exactly where the original next heading begins, and at EOF the original file
must end exactly where the block begins. `cmd_write`'s block already ends with
one blank line. The original file's own blank line before `## Out of scope`
comes before the inserted heading, so the insertion adds no stray lines.

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

    run:    2026-09-29T00:16:21Z
    commit: 9691cdd
    tree:   1c06ac8e6fbc9b5256782ecdca20a65b37d3f05c
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 90)
    PASS         lint (1s, observed 90, floor 1)
    PASS         typecheck (3s, observed 17)
    PASS         unit (31s, observed 452, floor 443)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 57746)
    PASS         harness (15s, observed 40)
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

