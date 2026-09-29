---
id: HARNESS-018
title: no pipe feeds an early-exiting grep under pipefail
slug: no-pipe-feeds-an-early-exiting-grep-unde
epic: 
type: fix
status: todo
phase: PLANNED
branch: story/HARNESS-018-no-pipe-feeds-an-early-exiting-grep-unde
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

<!-- Why this story exists. Link the epic and any wiki pages that constrain it.
     Name the REQUIRED gate that would fail if this story's artifact broke. If
     only an optional gate can, put it in required_gates above before RED:
     every required gate once passed over a story none of them exercised. -->

`missing_tokens()` in `.claude/tests/profile-counters.test.sh` runs
`printf '%s\n' "$text" | grep -qiF -- "$t"` for each token. `grep -q` exits at
its first match. If `$text` is bigger than the pipe buffer and the token appears
early, `printf` is still writing when the reader goes away, so it dies of
SIGPIPE. `_lib.sh` sets `set -uo pipefail`, so the pipeline's status is 141, and
the token is reported MISSING even though it is present. CI run 36503368294
(PR ryanczhang7/first-roblox#34, 2026-09-29) failed exactly this way:
`profile-counters.test.sh: line 319: printf: write error: Broken pipe`, then
`FAIL the Verified banner still names all seven pinned tools and both platform
verdicts`. A re-run with no code change went green. The failure is a race on
the pipe buffer, so it is intermittent.

This is the fifth instance of a defect family the harness has already
documented three times: `has_content` in `scripts/plan.sh`, `strip_comments |
grep -q` in `scripts/check-boundaries.sh`, and the discovery lines in
`scripts/doctor.sh`. Each fix so far was local to the place it was reported,
so the shape kept coming back. A survey on 2026-09-29 found it in 25 lines
across `.claude/tests/*.sh`, `scripts/*.sh` and `.claude/hooks/lib.sh`. Every
one of those files runs under `pipefail`. Most sites read small strings and
cannot lose the race today, but two can with realistic input:

- `scripts/gates.sh` decides BLOCKED and "no evidence of work" with
  `clean_log "$log" | grep -Eq`. `clean_log` is a `sed` over the gate's whole
  log. A gate whose log is large and whose evidence or launch-failure line comes
  early can be reported as `ran but produced no evidence of work` (a false FAIL
  of a required gate), or as a plain FAIL when it was BLOCKED.
- `json_is_true` in `.claude/hooks/lib.sh` pipes `$HOOK_INPUT` into `grep -qE`.
  `$HOOK_INPUT` is the tool call's JSON, which carries the whole file body on a
  `Write`.

So the fix is the rule, not the one line: **nothing pipes into a quiet `grep`**.
The reader gets its input from a here-string, a process substitution or a
`case`, so the writer is never in a pipeline whose status is read. Dropping
`pipefail` is not the fix, for the reason `check-boundaries.sh` records: it
would also hide the failures `pipefail` exists to catch.

Required gate that fails if this breaks: `harness`, whose `bash
scripts/selftest.sh` runs every `.claude/tests/*.test.sh`, including the new
`.claude/tests/pipe-readers.test.sh`.

## Acceptance criteria

<!-- Each AC is independently testable and phrased as observable behaviour.
     The Test Developer writes at least one failing test per AC.
     An AC that names a statistic, a metric or a threshold names a NEGATIVE
     CONTROL too: the deliberately broken input the metric must reject, and
     roughly what it should score. A criterion can be perfectly testable and
     still be blind to the defect it exists to catch, and that is more
     dangerous than a vague one - it survives review and goes green. -->

- **AC-1** — Given a text of at least 1.5 MiB whose first line contains a
  token, when `missing_tokens` (the function defined in
  `.claude/tests/profile-counters.test.sh`, run under `set -o pipefail`) is
  asked about that token, then it reports nothing missing, on every one of
  three consecutive calls. *Control:* a token that appears nowhere in the same
  text is still reported missing. The token check must not become a formality.
- **AC-2** — Given a gate whose output is at least 2 MB and whose first line is
  the one that matters, when `scripts/gates.sh` runs it, then (a) a gate that
  exits 0 with its evidence line first is `PASS`, not `ran but produced no
  evidence of work`, and (b) a gate that exits non-zero with a launch-failure
  line first (`command not found`) is `BLOCKED`, not `FAIL`. *Control:* a gate
  that exits 0 with the same 2 MB of output and no evidence line is still
  reported as `no evidence of work`.
- **AC-3** — No line of shell code in `scripts/*.sh`, `.claude/tests/*.sh` or
  `.claude/hooks/*.sh` pipes into a quiet `grep` (`-q`, a flag cluster
  containing `q` such as `-qiF` or `-Eq`, `--quiet` or `--silent`). This covers
  a pipe on the same line and a pipe whose `|` ends the previous line. Comments
  and heredoc bodies are data, not code, and are not counted. *Controls:* the
  scanner flags each of `printf '%s\n' "$x" | grep -qF -- y`,
  `clean_log "$l" | grep -Eq -- "$p"`, and `foo |` followed by
  `  grep -q bar` on the next line. It does not flag `foo || grep -q bar`,
  `grep -q bar <<< "$x"`, a `# ... | grep -q` comment, or a heredoc body line
  containing `| grep -q`.

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

**Files.** New: `.claude/tests/pipe-readers.test.sh`. It is ours. Upstream
ships no file of that name, so `scripts/refresh-harness.sh` will not delete it.
Changed by GREEN: every file the scanner reports at RED. Those are expected to
be `.claude/tests/{ci-local,harness-gate,lib,plan,profile-counters,project-counters}.test.sh`,
`scripts/{check-boundaries,classify,gates}.sh` and `.claude/hooks/lib.sh`.
Every one of these classifies as `harness`, so the phase lock permits writing
any of them in any phase. The only thing enforcing RED-before-GREEN here is
this contract. RED writes only `pipe-readers.test.sh`, and GREEN writes only the
files the scanner names.

Several of the changed files are upstream's (`gates.sh`, `check-boundaries.sh`,
`classify.sh`, `hooks/lib.sh` and most test files). A future
`refresh-harness.sh` may put the pipes back. AC-3's scanner lives in our own
file precisely so that such a refresh fails the `harness` gate instead of
silently reintroducing the flake.

**AC-1 harness.** The test extracts `missing_tokens` from
`profile-counters.test.sh` with awk (from `^missing_tokens() {` to the first
`^}`) and `eval`s it. It does not source the suite, which would run it. The big
text is `yes '<line>' | head -c 1572864` with the token on line 1, the same
1.5 MiB `boundaries.test.sh` uses: the pipe buffer varies between machines, and
this has to lose the race everywhere. The function's signature and output
(`missing_tokens <text> <token>...` prints one missing token per line) do not
change.

**AC-2 harness.** A `make_project_fixture` project, as `gates.test.sh` builds
one, with `write_conf` gates of the form
`{ printf 'Tests  47 passed (47)\n'; seq 1 300000; }` (about 2 MB). The needles
are the summary lines `PASS         unit`, `BLOCKED      unit` and
`no evidence of work`, which `gates.test.sh` already pins.

**AC-3 scanner.** A function in the test, `quiet_pipes <file>...`, prints
`file:line: text` for each offending line. It is awk only. It tracks heredoc
bodies (`<<WORD`, `<<-WORD`, `<<'WORD'`, `<<"WORD"`, but not `<<<`) and skips
lines whose first non-blank character is `#`. A `|` counts as a pipe only when
it is not part of `||`. The file list comes from the three globs in AC-3, which
are literal globs rather than `classify.sh --list`, because the category of
every one of these paths is `harness` and the question is "shell the harness
runs", not "source". The controls are written to probe files in a temp
directory and scanned by the same function.

**Replacement idioms, GREEN's choice per site:** `grep -q … <<< "$var"` for a
variable; `grep -q … < <(producer)` for a stream (`clean_log`, where a here-string
would drop NUL bytes with a warning); `case` where the question is a prefix
(`head -1 "$f"`). None of them may drop `pipefail` or add `|| true`.

**Oracle partition.** All three ACs are *mechanical*: exact needles, exact
counts.

**Tooling.** Bash, awk and coreutils only (`.claude/harness/rules.md`,
Portability). There are no test dependencies.

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

**DV-1: the AC-1 and AC-2 controls, earned by a mutation.** The two controls
(`a token that appears nowhere is still reported missing`, `a large gate with
no evidence line is still no evidence of work`) pass in RED. That is because
today's defect fails closed, and a closed failure agrees with them. After GREEN,
each one **must** fail against a fix that over-corrects:
`missing_tokens` that never reports anything, and an evidence check that never
reports no-evidence. RED cannot run this, because there is no fix to mutate
yet. **Owner: GATES.**

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
Planned by `bash scripts/plan.sh write HARNESS-018` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `1.5` (source), `boundaries.test.sh` (test), `check-boundaries.sh` (source) (+8 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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

## Out of scope

<!-- Explicit non-goals. Prevents the Feature Developer from over-building. -->

- Other early-exiting readers (`| head -1`, `grep -m1`). Every current one sits
  inside a `$(...)` whose status nobody reads. The output is still correct
  there, and SIGPIPE only makes it quieter.
- Discovery and gate *commands* inside project.conf, profile documents and
  heredoc fixtures. `doctor.sh` already runs discovery with `set +o pipefail`,
  and the profiles teach that separately.
- Fixing the same shape upstream in `../agentic-dev-harness`. That is worth
  reporting, but it is not this repository's change.

## Design notes

<!-- Filled by the Lead Designer for user-facing stories: layout, states,
     tokens, accessibility requirements. Omit for non-UI stories. -->

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

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

<!-- Written by scripts/gates.sh itself on every full run, stamped with the
     commit and a hash of the code it ran against. Do not paste or edit it:
     check-boundaries.sh refuses a PR whose recorded run does not match the
     code being merged. -->

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

