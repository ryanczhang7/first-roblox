---
id: HARNESS-016
title: Every contract helper raises through the shared raiser
slug: every-contract-helper-raises-through-the
epic: 
type: chore
status: in-progress
phase: GATES
branch: story/HARNESS-016-every-contract-helper-raises-through-the
depends_on: [HARNESS-011]   # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

`HARNESS-011` created `tests/helpers/Contract.luau`: `Contract.fail(msg)` is
`error(msg, 0)`, which does not truncate, and `Contract.firstFew` is the shared,
counted message-builder. It converted four helpers (`Ring`, `Projection`,
`LobbyGate`, `RoundEnding`) and deliberately left the rest for this story. The
follow-up its `## Out of scope` required.

What remains, counted on 2026-09-28 (`HARNESS-011`'s PLANNED re-read):

| Helper | Raises through | Sites |
|---|---|---|
| `ClockContract` | bare `assert` | 11 |
| `RngContract` | bare `assert` | 15 |
| `PhaseMachineContract` | bare `assert` | 11 |
| `TuningSpec` | bare `assert` | 5 |
| `TelemetryEmitContract` | bare `assert` | 48 |
| `NetContract` | private `check` → `error(msg, 2)` | 48 |
| `PhaseContract` | private `check` | 22, + 1 `assert` |
| `RateContract` | private `check` | 15 |
| `RejectionContract` | private `check` | 25 |
| `TelemetryContract` | private `check` | 11 |

Two defects, one per shape:

- **Bare `assert`** truncates at 511 characters (`docs/wiki/stack.md`) and
  builds its message on every passing run.
- **Private `check`** avoids the truncation but still builds eagerly. Each
  wrapper's doc comment also quotes the wrong cap ("512 characters after the
  location prefix"). There are five copies of one answer, which is the drift
  `rules.md` warns about.

**Re-count before leaving PLANNED.** These numbers were taken while
`HARNESS-011` was being planned and will have moved.

`tests/helpers/Fakes.luau` (2 sites) is a stub, not a contract, and is out of
scope.

## Acceptance criteria

<!-- Frozen once this story leaves PLANNED. A change goes in ## Amendments. -->

- **AC-1**: Given every contract helper listed in `## Context`, then none calls
  bare `assert` or `error` directly, and none defines a private raiser. Every
  failure goes through `Contract.fail`. This extends the in-scope set of
  `HARNESS-011`'s AC-4 guard (`tests/shared/contract_raise_test.luau`), whose
  enumeration still comes from `scripts/classify.sh`.
  *Control:* one reintroduced site in any newly covered helper is reported by
  file and line.
- **AC-2**: Given a helper that accumulates violations, then it reports them
  through `Contract.firstFew`, and a passing check built with it counts zero
  builds. *Control:* non-zero on a failing check.
- **AC-3**: No comment in `tests/` states the `assert` cap as 512.
- **AC-4**: The full suite reports `0 failed`, above the `unit` floor, with no
  existing needle or message changed.

## Contract

<!-- Amendable by SCAFFOLD in place, with a reason. -->

### Re-count at PLANNED (2026-09-28, `main` @ `905182f`)

Counted with the AC-1 guard's own instrument (`SourceScan.hitsIn` over
`classify.sh --list test tests/helpers`), plus `check(` references minus the
definition. **The filed table is unchanged:**

| Helper | bare `assert` | direct `error` | private `check(` calls | accumulating checks |
|---|---|---|---|---|
| `ClockContract` | 11 | 0 | — | 0 |
| `RngContract` | 15 | 1 (fixed message, line 237) | — | 0 |
| `PhaseMachineContract` | 11 | 0 | — | 0 |
| `TuningSpec` | 5 | 0 | — | 0 |
| `TelemetryEmitContract` | 48 | 1 (reports `violations[1]`, line 1415) | — | 1, reports the first only |
| `NetContract` | 0 | 1 (the wrapper body) | 48 | 9, all `table.concat(violations, "\n")` |
| `PhaseContract` | 1 | 1 (the wrapper body) | 22 | 6, all `table.concat` |
| `RateContract` | 0 | 1 (the wrapper body) | 15 | 8, all `table.concat` |
| `RejectionContract` | 0 | 1 (the wrapper body) | 25 | 14, all `table.concat` |
| `TelemetryContract` | 0 | 3 (the wrapper body; a private `firstFew`'s caller has none; a deliberately exploding sink, line 171) | 11 | 8: 6 `table.concat`, 2 private `firstFew` (6 and 8) |

Raising helpers **not** in scope, and why: `Fakes.luau` (a stub, as filed), and
every `*Stubs.luau`, `MachineStubs.luau` and `SourceScan.luau`. The stubs raise
on purpose — they are the defective implementations the controls feed to the
contracts — and `SourceScan` is an instrument, not a contract. AC-1 names "every
contract helper listed in `## Context`", which is the ten above.

### The raiser and the builder

No new export. `tests/helpers/Contract.luau` is used as `HARNESS-011` left it:
`Contract.fail(msg): never` (`error(msg, 0)`) and the counted
`Contract.firstFew(list, count)`. Its signature does not change.

**Binding name.** `Contract`, except in `TelemetryEmitContract.luau`, which
already binds `Contract` to `PhaseMachineContract`: there it is `Raise`, as in
`LobbyGateContract` and `RoundEndingContract`.

### The call shape

Every raise becomes `if <negated condition> then Contract.fail(<message>) end`,
with the message **byte for byte** as it was. The five private `check` wrappers
and their "512 characters after the location prefix" comments are deleted. So is
`TelemetryContract`'s private `firstFew`.

**PO-1 (the user, at PLANNED): every accumulating check reports through
`Contract.firstFew`.** That is all 45 of them.
- The 43 that print every violation with `table.concat(violations, "\n")`
  become `Contract.firstFew(violations, #violations)`. With `count >= #list`,
  `firstFew` returns `table.concat(list, "\n") .. ""`, so the output is
  byte-identical. No message changes, which AC-4 requires. **Do not** use 8
  here: that rewords 43 messages, and `## Out of scope` forbids it.
- `TelemetryContract`'s 2 private-`firstFew` sites call `Contract.firstFew`
  with their existing counts, 6 and 8.

**PO-2 (lead-po): `TelemetryEmitContract`'s one accumulating check keeps
`violations[1]`.** It reports one element, not a list. `firstFew(violations, 1)`
would append `... and N more`, which is a message change. Its `error(_, 2)`
becomes `Raise.fail`.

**PO-3 (lead-po): `TelemetryContract`'s exploding sink (line 171) goes through
`Contract.fail` too.** It is a simulated fault, not a contract report, but AC-1
reads "none calls bare `assert` or `error` directly", and nothing about a fault
needs `error` specifically. The level goes from 1 to 0, so the position prefix is
dropped. SCAFFOLD confirms that no test matches that message anchored or by its
prefix, and records the search.

*Amended in SCAFFOLD (2026-09-28), in place, with the reason:* the re-count row
above misdescribed Telemetry's third `error`. It is not "a private `firstFew`'s
caller". It is a second fake sink (line 701 at PLANNED) that raises the
**table** `{ code = 503 }`, so that `raisingEmitDoesNotPropagate` sees a
non-string error. PO-3 covers it too: `Contract.fail(({ code = 503 } :: any))`.
The cast is needed because `fail` takes a `string`, and the contract pins that
signature, so it is not widened. Lua adds position information only to a
string, so the level is irrelevant here and the value raised is the same table.
*Search recorded:* the only other reader of `sink exploded` is
`telemetry_controls_test.luau:420`, a `names()` over plain `string.find`, which
is unanchored. Nothing reads the table error's message.

### AC-3's instrument

The scan is over **comment text only**, in every file that
`classify.sh --list test tests` returns. Code and string literals are excluded:
`contract_raise_test.luau` legitimately carries "512" in strings (AC-1's control
and AC-3's own needle). The needle is `512 character` (it matches the plural as
well). A hit is reported as `path:line`.
- *Red run expected:* five hits, one in each wrapper's doc comment (Net:62,
  Phase:70, Rate:76, Rejection:71, Telemetry:111).
- *Control:* a comment carrying the phrase, appended to a real helper's text in
  memory, is reported at exactly that `path:line`. A string literal carrying it is
  **not** reported. That second half is what keeps the scan off code.
- The test file must not write the phrase in its own comments. Build the needle
  so that the scan cannot hit itself.

### Phase path: PLANNED → SCAFFOLD → GATES → REVIEW → DONE

Every code file here classifies as `test`, as it did in `HARNESS-011`, so GREEN
and GATES cannot write the fix. That story's `## Notes` ("The phase path, and the
option not taken") applies unchanged. **SCAFFOLD keeps the ordering**, and each
red is pasted into `## Scaffold inventory`:

1. Extend AC-1's `IN_SCOPE` to the ten helpers. Run it: red, listing the sites
   above.
2. Write AC-3's test. Run it: red, with the five hits.
3. Add AC-2's new `PASSING`/`FAILING` cases, one pair per newly reached helper
   (Net, Phase, Rate, Rejection, Telemetry): a check on its correct stub, and the
   same or a sibling check on a control stub that its controls test already
   asserts fails. Run them. The control is red: the counter sees 0 builds,
   because nothing calls `Contract.firstFew` yet. Then switch the **builders
   only** to `Contract.firstFew` and leave the raises eager. Run again: `AC-2`
   is red, with one build per passing case. That is the red that shows the eager
   build is real.
4. *Then* convert the raises. Everything is green.

### Oracle partition

| AC | Kind | Instruction |
|---|---|---|
| AC-1 | **Mechanical** | Extend the existing guard's `IN_SCOPE`. The existing control iterates it, so it covers the new helpers without new code. The enumeration stays with `classify.sh`. |
| AC-2 | **Mechanical** | The counter is zero on a passing case and non-zero on a failing one, per helper. Both halves. |
| AC-3 | **Mechanical** | Anchor on comment text, report `path:line`, and use the two-sided control above. |
| AC-4 | **Settled** | Read out `450 passed, 0 failed` (measured at PLANNED, 21s), floor `443`. After SCAFFOLD: 450 plus the new tests, 0 failed. Show "no message changed" as HARNESS-011 did: diff every string-literal line before and after, and require that every existing controls needle still matches. |

### The required gate that would fail if this artifact broke

`unit` (`lune run test`) is `required`, and it runs `contract_raise_test.luau`
and every helper. `lint` (required) also reads `tests`. No optional gate is
involved, so `required_gates` stays empty.

### Changed signatures

None. The private `check` and `firstFew` are `local` and are not exported. The
`.check` fields in the `*_controls_test.luau` files are table entries, not these
functions. That was checked by grep, not assumed. The caller list is empty.

### Test-only dependencies

None.

## Deferred verifications

<!-- Owner: the phase that runs it. Result pasted in by that phase. -->

**DV-1: AC-1's guard catches a site reverted in a newly covered helper.** With
one `Contract.fail` site in `NetContract.luau` put back to a bare `assert`
through `scripts/mutate.sh`, `lune run test` fails, and AC-1's test names
`tests/helpers/NetContract.luau:<line>: assert`. **Owner: GATES.**

**DV-2: AC-2's counter sees a builder reverted to `table.concat`.** With one
`Contract.firstFew(violations, #violations)` put back to
`table.concat(violations, "\n")`, in the check that AC-2's failing case uses for
that helper, exactly one assertion fails: AC-2's control, "raised, but the
counter saw 0 builds". **Owner: GATES.**

**DV-3: a wrong value, not a missing call.** With `#violations` → `1` at one
site, the message gains `... and N more` and loses violations. Whether any test
catches this is **not predicted**. It is measured and recorded either way, as
the limit of AC-4's "no message changed", which the literal-line diff shows and
no test pins. **Owner: GATES.**

**DV-4: AC-3 catches a reintroduced comment.** With a doc comment in one helper
changed to say `512 characters`, AC-3's test names that `path:line`. **Owner:
GATES.**

#### Run in GATES (lead-po, 2026-09-28), before `gates.sh`

**DV-1: predicted exactly one failure.**

    $ bash scripts/mutate.sh tests/helpers/NetContract.luau '263s/Contract\.fail(/assert(false, /' -- \
        bash -c 'lune run test 2>&1 | grep -E "^  FAIL|^  tests/helpers/[A-Za-z]+\.luau:[0-9]+|saw 0|^[0-9]+ passed"'
      263 - 		Contract.fail(`AC-1: a valid call raised: {tostring(result)}`)
      263 + 		assert(false, `AC-1: a valid call raised: {tostring(result)}`)
      FAIL  tests/shared/contract_raise_test.luau :: AC-4: no in-scope contract helper raises except through Contract.fail
      tests/helpers/NetContract.luau:263: assert
    451 passed, 1 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .../tests_helpers_NetContract.luau.20260928T230444Z.24147.bak) ===

**DV-2: predicted exactly one failure, the AC-2 control naming Rate.**

    $ bash scripts/mutate.sh tests/helpers/RateContract.luau \
        '325s/Contract\.firstFew(violations, #violations)/table.concat(violations, string.char(10))/' -- ...
      325 - 					Contract.firstFew(violations, #violations)
      325 + 					table.concat(violations, string.char(10))
      FAIL  tests/shared/contract_raise_test.luau :: AC-2 control: a failing contract check does build its message, and the counter sees it
      RateContract, NET-003 AC-2, on the shared-timestamp wrapper: raised, but the counter saw 0 builds
    451 passed, 1 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .../tests_helpers_RateContract.luau.20260928T232650Z.74923.bak) ===

`string.char(10)` stands in for `"\n"`: the first attempt's `"\\n"` reached sed
with its backslash halved, so sed wrote a real newline. That left RateContract
unparseable, and **`lune run test` hung instead of failing**. It had been
running for about 20 minutes when the `lune` child alone was sent SIGTERM;
`mutate.sh` then restored the file and verified it (`command exited 1; restored
(verified byte-for-byte ...230513Z.25859.bak)`). That run is discarded. See
`## Notes`.

**DV-3: not predicted. Measured: caught, by an existing controls needle.**

    $ bash scripts/mutate.sh tests/helpers/RateContract.luau '325s/#violations)/1)/' -- ...
      325 - 					Contract.firstFew(violations, #violations)
      325 + 					Contract.firstFew(violations, 1)
      FAIL  tests/net/rate_controls_test.luau :: AC-2 control: a wrapper with one shared last-accepted timestamp passes AC-1 and every other check, and fails AC-2 alone - B is refused at the instant A is limited (1 of 28)
    451 passed, 1 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .../tests_helpers_RateContract.luau.20260928T232540Z.71734.bak) ===

At this site, AC-4's "no message changed" is also pinned by a test, not only by
the literal-line comparison: the controls needle sits past the first violation.
That holds only where a needle does. It is not a claim about all 45 sites.

**DV-4: predicted exactly one failure, naming the line.**

    $ bash scripts/mutate.sh tests/helpers/NetContract.luau \
        '70s/^-- Unique per process/-- assert keeps 512 characters. Unique per process/' -- ...
      FAIL  tests/shared/contract_raise_test.luau :: HARNESS-016 AC-3: no comment in tests/ quotes the assert cap as 512
      tests/helpers/NetContract.luau:70
    451 passed, 1 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .../tests_helpers_NetContract.luau.20260928T232608Z.73192.bak) ===

No `.bak` remains under `.claude/state/mutations/`.

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write HARNESS-016` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `Contract.fail` (source), `Contract.firstFew` (source), `Fakes.luau` (source) (+11 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

**Resolved:**

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

- PLANNED — `lead-po`, run in the orchestrating session: **Opus 5.5**
  (`claude-opus-5-5`). As planned.
- SCAFFOLD — `lead-po`, run in the orchestrating session with no subagent
  dispatch: **Opus 5.5** (`claude-opus-5-5`). As planned. The RED row (`fable`)
  is not reached on this phase path, and is no verdict either way.

## Test plan

Everything is in `tests/shared/contract_raise_test.luau`, and the required `unit`
gate runs it. Two tests are new; two are extended by data.

| Test | AC | What makes it fail |
|---|---|---|
| `AC-4: no in-scope contract helper raises except through Contract.fail` (extended: `IN_SCOPE` 4 → 14) | AC-1 | A code-level `assert` or `error` in any of the 14 helpers, reported as `path:line: symbol`. It also fails if `classify.sh --list test tests/helpers` stops returning one of them. |
| `AC-4 control: one reintroduced bare assert or direct error is reported by file and line` (extended by the same list) | AC-1 control | An appended `assert(...)` or `error(...)` in any of the 14 is not reported at exactly `path:<line>`, or it moves the count by anything other than 1. |
| `AC-2: a passing contract check never builds its failure message` (+5 cases) | AC-2 | The counter reads non-zero after a passing check: Net NET-001 AC-2, Phase NET-002 AC-4, Rate NET-003 AC-2, Rejection TEL-003 AC-6, Telemetry TEL-001 AC-6, each on its correct stub. |
| `AC-2 control: a failing contract check does build its message, and the counter sees it` (+5 cases) | AC-2 control | The same checks, on the control stub that their own controls test asserts they fail (`booleanFalse`, `firstEntryOnly`, `sharedTimestamp`, `perPlayerOnly`, `acceptNestedTable`), either pass or build nothing. |
| `HARNESS-016 AC-3: no comment in tests/ quotes the assert cap as 512` (new) | AC-3 | Any **comment** line under `classify.sh --list test tests` contains `512 character`. Only comments are read (`SourceScan.commentsOnly`, new), and each hit is reported as `path:line`. |
| `HARNESS-016 AC-3 control: a comment quoting 512 is reported by line, a string saying it is not` (new) | AC-3 control | That phrase appended to `RingContract`'s real text as a comment is not reported at exactly that line, **or** the same phrase appended as a string literal is reported. |

**AC-4** is the runner's own final line, `452 passed, 0 failed`: 450 before,
plus the two new tests. The floor `floor | unit | 443` holds it up from below.
"No existing needle or message changed" rests on two things. First, every
existing controls test is green; each of them asserts its helper's messages by
needle. Second, there is the string-literal comparison in `## Scaffold inventory`.

## Scaffold inventory

<!-- REQUIRED: this chore runs under SCAFFOLD. Every code file here classifies
     as `test`; no production source changes. -->

No production source changed. Every file classifies as `test` or `docs`. The
output:

    $ git status --porcelain | awk '{print $2}' | xargs bash scripts/classify.sh
    docs	docs/backlog/stories/HARNESS-016.md
    test	tests/helpers/ClockContract.luau
    test	tests/helpers/NetContract.luau
    test	tests/helpers/PhaseContract.luau
    test	tests/helpers/PhaseMachineContract.luau
    test	tests/helpers/RateContract.luau
    test	tests/helpers/RejectionContract.luau
    test	tests/helpers/RngContract.luau
    test	tests/helpers/SourceScan.luau
    test	tests/helpers/TelemetryContract.luau
    test	tests/helpers/TelemetryEmitContract.luau
    test	tests/helpers/TuningSpec.luau
    test	tests/shared/contract_raise_test.luau

| File | Change | Covered by |
|---|---|---|
| `tests/helpers/ClockContract.luau` | 11 `assert` → `Contract.fail` | AC-1 guard; `clock_controls_test` green |
| `tests/helpers/RngContract.luau` | 15 `assert` and 1 `error` → `Contract.fail` | AC-1; `rng_controls_test` |
| `tests/helpers/PhaseMachineContract.luau` | 11 `assert` → `Contract.fail` | AC-1; `phase_machine_controls_test` |
| `tests/helpers/TuningSpec.luau` | 5 `assert` → `Contract.fail` | AC-1; `tuning_controls_test` |
| `tests/helpers/TelemetryEmitContract.luau` | 48 `assert` → `Raise.fail`, and the one `error(_, 2)` too (PO-2) | AC-1; `telemetry_emit_controls_test` |
| `tests/helpers/NetContract.luau` | 48 `check` → `Contract.fail`; wrapper and its 512 comment deleted; 9 builders → `Contract.firstFew(violations, #violations)` | AC-1, AC-2, AC-3; `net_controls_test` |
| `tests/helpers/PhaseContract.luau` | 22 `check` and 1 `assert` → `Contract.fail`; wrapper deleted; 6 builders | same; `phase_controls_test` |
| `tests/helpers/RateContract.luau` | 15 `check`; wrapper deleted; 8 builders | same; `rate_controls_test` |
| `tests/helpers/RejectionContract.luau` | 25 `check`; wrapper deleted; 14 builders | same; `rejection_controls_test` |
| `tests/helpers/TelemetryContract.luau` | 11 `check`, 2 fake-sink `error`s (PO-3) → `Contract.fail`; wrapper and private `firstFew` deleted; 6 builders + 2 counted (6 and 8) | same; `telemetry_controls_test` |
| `tests/helpers/SourceScan.luau` | the lexer lifted into a local `walk(text, want)`; `codeOnly` unchanged in behaviour; new `commentsOnly` | `codeOnly`: every existing guard over it (`source_guard_test` and others), green. `commentsOnly`: the AC-3 control, both halves |
| `tests/shared/contract_raise_test.luau` | the test changes in `## Test plan` | itself; each change observed red below |

**Totals.** 212 call sites converted (91 `assert` + 121 `check`), plus 4 direct
`error`s (Rng 1, TelemetryEmit 1, Telemetry 2). Five wrappers were deleted, and
45 builders now go through `Contract.firstFew`.

**How the conversion was done.** As in `HARNESS-011`, a throwaway Lune script
(in the gitignored `.claude/state/scratch/`, not committed) found every
statement-position `assert(`/`check(` through `SourceScan.codeOnly`, split the
first top-level comma, and emitted `if <negation> then <Raiser>.fail(<message
text, byte for byte>) end`. For the negation, a single top-level `==`/`~=` with
no `and`/`or`/`not`/relational operator was swapped; anything else became
`not (…)`. stylua reflowed the result. The script printed
`11, 15, 11, 48, 48, 23, 15, 25, 11, 5 converted` = 212. It reported no site
that was not a statement and none that had no message. The builders were
switched with one substitution per file, `table.concat(violations, "\n")` →
`Contract.firstFew(violations, #violations)`, which leaves no remaining
`table.concat(violations` in any of the five files.

**No message changed: the check.** For each of the ten helpers, a probe built
the in-order sequence of string-literal characters, before (`git show HEAD:`)
and after. It used `codeOnly` and `commentsOnly` to exclude code and comments.
Four differences were expected, and those were normalised away: the `"\n"`
separator arguments that `firstFew` now supplies, Telemetry's deleted private
`firstFew` literals, the `]]` of each deleted wrapper doc comment, and the new
`"./Contract"` require. The result:

    IDENTICAL 456 tests/helpers/ClockContract.luau
    IDENTICAL 1142 tests/helpers/RngContract.luau
    IDENTICAL 789 tests/helpers/PhaseMachineContract.luau
    IDENTICAL 8769 tests/helpers/TelemetryEmitContract.luau
    IDENTICAL 8878 tests/helpers/NetContract.luau
    IDENTICAL 4286 tests/helpers/PhaseContract.luau
    IDENTICAL 5307 tests/helpers/RateContract.luau
    IDENTICAL 10037 tests/helpers/RejectionContract.luau
    IDENTICAL 4085 tests/helpers/TelemetryContract.luau
    IDENTICAL 1484 tests/helpers/TuningSpec.luau

### Red run 1: AC-1's guard over the ten new helpers, before any conversion

    $ lune run test
      pass  tests/shared/contract_raise_test.luau :: AC-4 control: one reintroduced bare assert or direct error is reported by file and line
      FAIL  tests/shared/contract_raise_test.luau :: AC-4: no in-scope contract helper raises except through Contract.fail
            AC-4: 100 raise(s) in the in-scope helpers do not go through Contract.fail:
      tests/helpers/ClockContract.luau:31: assert
      ...
    449 passed, 1 failed

The lines it named, per file: Clock 11, Rng 16, PhaseMachine 11, TuningSpec 5,
TelemetryEmit 49, Net 1, Phase 2, Rate 1, Rejection 1, Telemetry 3. That is 100:
91 `assert` + 9 `error`, matching the PLANNED re-count exactly. Each wrapper is
one `error` standing in for all its callers, as in `HARNESS-011`'s red run 3.
The control passed over all 14 helpers in the same run.

### Red run 2: AC-3, before any wrapper was deleted

    $ lune run test
      pass  tests/shared/contract_raise_test.luau :: HARNESS-016 AC-3 control: a comment quoting 512 is reported by line, a string saying it is not
      FAIL  tests/shared/contract_raise_test.luau :: HARNESS-016 AC-3: no comment in tests/ quotes the assert cap as 512
            ...contract_raise_test:365: 5 comment line(s) quote the cap as "512 character"; it is 511:
      tests/helpers/NetContract.luau:62
      tests/helpers/PhaseContract.luau:70
      tests/helpers/RateContract.luau:76
      tests/helpers/RejectionContract.luau:71
      tests/helpers/TelemetryContract.luau:111
    450 passed, 2 failed

That is exactly the five lines the contract predicted. `contract_raise_test.luau`
carries the phrase in two strings, and neither is a hit, so the string half of
the control is exercised by the real tree as well as by the probe.

### Red run 3a: AC-2's control, before any builder was switched

    $ lune run test
      FAIL  tests/shared/contract_raise_test.luau :: AC-2 control: a failing contract check does build its message, and the counter sees it
            ...contract_raise_test:326: the counter did not see a failing check build:
      NetContract, NET-001 AC-2, on the boolean-false wrapper: raised, but the counter saw 0 builds
      PhaseContract, NET-002 AC-4, on the first-entry-only wrapper: raised, but the counter saw 0 builds
      RateContract, NET-003 AC-2, on the shared-timestamp wrapper: raised, but the counter saw 0 builds
      RejectionContract, TEL-003 AC-6, on the per-player reporter: raised, but the counter saw 0 builds
      TelemetryContract, TEL-001 AC-6, on the accept-nested-table Event
      pass  tests/shared/contract_raise_test.luau :: AC-2: a passing contract check never builds its failure message
    449 passed, 3 failed

**The fifth line has lost its reason.** The control raised its report through
bare `assert`, so the report was cut at 511 characters. That is this story's
defect, observed in its own guard. See "The guard's own raises" below.

### Red run 3b: AC-2, builders switched and raises still eager

    $ lune run test
      pass  tests/shared/contract_raise_test.luau :: AC-2 control: a failing contract check does build its message, and the counter sees it
      FAIL  tests/shared/contract_raise_test.luau :: AC-2: a passing contract check never builds its failure message
            ...contract_raise_test:302: a passing check built its failure message:
      NetContract, NET-001 AC-2, on the correct wrapper: 1 build(s)
      PhaseContract, NET-002 AC-4, on the correct wrapper: 1 build(s)
      RateContract, NET-003 AC-2, on the correct wrapper: 1 build(s)
      RejectionContract, TEL-003 AC-6, on the correct bundle: 1 build(s)
      TelemetryContract, TEL-001 AC-6, on the correct Event: 1 build(s)
    449 passed, 3 failed

One eager build per passing check in all five helpers: the private `check`'s
argument was evaluated on every passing run. In the same run the control passed,
so the counter does increment.

### The guard's own raises

Red run 3a showed `contract_raise_test.luau` itself destroying evidence. Its
four accumulating reports (AC-2, the AC-2 control, the AC-4 control and
HARNESS-016 AC-3) raised through bare `assert`, and now that the case lists have
grown, those reports pass 511. They now raise through `Contract().fail`, as the
file's AC-4 test already did with `error(_, 0)`. The needles and conditions are
unchanged. AC-1 does not require this, because the guard is not a contract
helper. It is done because a guard that truncates its own report is the defect
this story exists to remove.

Earned by a mutation that makes the longest of those reports fire. The counter
is disabled, so every failing case reports:

    $ bash scripts/mutate.sh tests/helpers/Contract.luau 's/^\tbuilds += 1$/\t-- builds += 1/' -- ...
      54 - 	builds += 1
      54 + 	-- builds += 1
      FAIL  tests/shared/contract_raise_test.luau :: AC-2 control: a failing contract check does build its message, and the counter sees it
      RingContract, SEAT-001 AC-1, on a generator that allows fixed points: raised, but the counter saw 0 builds
      ProjectionContract, SEAT-002 AC-2, on copy-and-remove-sigma: raised, but the counter saw 0 builds
      NetContract, NET-001 AC-2, on the boolean-false wrapper: raised, but the counter saw 0 builds
      PhaseContract, NET-002 AC-4, on the first-entry-only wrapper: raised, but the counter saw 0 builds
      RateContract, NET-003 AC-2, on the shared-timestamp wrapper: raised, but the counter saw 0 builds
      RejectionContract, TEL-003 AC-6, on the per-player reporter: raised, but the counter saw 0 builds
      TelemetryContract, TEL-001 AC-6, on the accept-nested-table Event: raised, but the counter saw 0 builds
    451 passed, 1 failed
    === mutate: command exited 0; restored (verified byte-for-byte against .../tests_helpers_Contract.luau.20260928T230052Z.17397.bak) ===

All seven lines arrive whole, about 650 characters in all, where red run 3a lost
the fifth line's reason. Exactly one assertion fails. This is also
`HARNESS-011`'s mutation 5, re-run over the widened case list: the zero half
passes, and the control alone catches a counter that never increments.

### After

    $ lune run test | tail -1
    452 passed, 0 failed

`bash scripts/gates.sh --fast`, in SCAFFOLD: format PASS (observed 90), lint PASS
(90, floor 1), typecheck PASS (17), unit PASS (452, floor 443, 155s), build PASS.
harness FAIL on `project-counters: 39 passed, 1 failed`. The one failure is the
precondition `the working tree carries no stray .luau files`, listing the 12
modified files. That is the uncommitted tree, as it was for `HARNESS-011` and
`SEAT-003`, and it clears on commit. No file was added, so the format and lint
counts stay at 90 and `BASE_FORMAT`/`BASE_LINT` need no edit.

**Timing, for GATES and CI.** On this machine the plain suite took anywhere from
21s to 3m31s over this session on the same code, and `unit` took 155s in
`--fast`. That is machine variance: the file under change times at about 12s by
itself. Most of that 12s is the two `classify.sh` scans. The new AC-3 scan over
`tests` costs about 7s, forked from bash. `HARNESS-011`'s CI run took 4s for
`unit`, so the close-out must re-read CI timings rather than assume them.

## Out of scope

- Re-tuning any `firstFew` count, rewording any message, or changing what any
  check asserts.
- `Fakes.luau`.

## Notes

Filed by the Lead PO at `HARNESS-011`'s GATES, 2026-09-28. The phase path,
contract and oracle partition are set when it leaves PLANNED. `HARNESS-011`'s
`## Contract` ("Phase path") explains why a conversion of test files runs under
SCAFFOLD rather than RED → GREEN, and that reasoning applies here unchanged.

`HARNESS-011` GATES found that its AC-1 test does not pin the raiser's *level*
(0 vs 2), because a direct `pcall(Contract.fail, …)` makes level 2 add no
prefix. No criterion depends on it. If this story wants the level pinned, it
needs a test that calls `fail` from a nested Luau function.

### PO decisions at PLANNED → SCAFFOLD (2026-09-28)

- **PO-1 (the user).** AC-2 is read as covering *every* accumulating check (45),
  not only the private `firstFew` copy (2). The user chose it over the narrower
  reading in this session. Messages are kept byte-identical by passing
  `#violations` as the count (`## Contract`, "The call shape").
- **PO-2, PO-3 (lead-po).** TelemetryEmit's `violations[1]` report is kept.
  Telemetry's exploding sink goes through `Contract.fail`. Reasons are in
  `## Contract`.
- **No amendment.** The criteria text is unchanged. PO-1 settles a reading; it
  does not change the text.

**Epic done-when:** `epic:` is empty, so there is nothing to check.

**Not pinned, deliberately:** the raiser's *level* (0 vs 2), which `HARNESS-011`
GATES found unpinned. No criterion here names it, and adding a test for it would
be scope this story does not claim.

### The freeze, SCAFFOLD → GATES

`bash scripts/frozen.sh snapshot` over the 12 test files, taken right after
`phase.sh set HARNESS-016 GATES`. Verified after the deferred verifications and
before the GATES commit:

    frozen: OK — 12 path(s) unchanged since the snapshot for HARNESS-016

### Operational hazard: a helper that does not parse hangs the runner

DV-2's first attempt left `RateContract.luau` unparseable (see
`## Deferred verifications`). `lune run test` did not report a LOAD FAIL. It
ran without end, about 20 minutes, until its `lune` child was sent SIGTERM. The
`mutate.sh` restore trap then ran correctly, because only the child was
terminated. Two lessons. Bound a mutation's command with `timeout`, as DV-2's
re-run did. And a mutation expression containing a backslash should be avoided
in this shell: `"\n"` arrived at sed as `"\n"`. This was not investigated
further, because it is outside this story.
