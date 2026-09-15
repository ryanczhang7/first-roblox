---
id: ROUND-001
title: Clock and randomness are injected, and nothing else may read them
slug: clock-and-randomness-are-injected-and-no
epic: EPIC-01
type: feature
status: done
phase: DONE
branch: story/ROUND-001-clock-and-randomness-are-injected-and-no
depends_on: [BOOT-001]
required_gates: []
---

## Context

`docs/wiki/architecture.md` §2 states a hard requirement: **the clock and the
random source are injected from the very first story**, because retrofitting
either means rewriting the phase machine and the instance generator. The
`roblox-luau` profile says the same thing under "Faking time" and "Faking
randomness", and calls it an architecture decision rather than a testing detail.

This is that story. It is small on purpose and everything in EPIC-01 and EPIC-02
depends on it.

The guard test is the half that will be tempting to skip. Two modules with clean
interfaces are worth nothing if the third module written next week calls
`os.clock()` directly — and nothing in the gates would notice, because a direct
`os.clock()` call type-checks, lints and passes every test that does not happen to
depend on the time.

**Which required gate would fail if this story's artifact broke:** `unit`. The
seeded-reproducibility tests and the guard test both run there.

## Acceptance criteria

- **AC-1** — Given a manual clock created at `t = 100`, when it is advanced by 5
  and then by 2.5, then `now()` returns `100`, `105` and `107.5` in turn, and
  returns the same value on repeated calls between advances.
- **AC-2** — Given two `Rng` instances created from the same seed, when the same
  sequence of `nextInteger` and `shuffle` calls is made on each, then the two
  produce identical results; and given two instances from different seeds, the
  sequences differ.
  *Control:* an `Rng` that ignores its seed — always returning the same stream —
  passes the first half and **must fail** the second half. A test that only
  asserts reproducibility is satisfied by a constant.
- **AC-3** — Given an `Rng`, when `derive("a")` and `derive("b")` are taken from
  it, then drawing any number of values from the `"a"` sub-stream does not change
  any value subsequently drawn from `"b"`, and `derive` with the same label on two
  same-seeded parents yields identical sub-streams.
  *Control:* an implementation where `derive` returns the parent itself passes the
  same-label test and **must fail** the independence test.
- **AC-4** — Given a list of `n` distinct values, when `shuffle` is called, then
  the result is a permutation of the input — same multiset, same length — and the
  **input list is not mutated**.
- **AC-5** — Given the set of source modules reported by
  `bash scripts/classify.sh --list source src`, when each is scanned, then no
  module other than `src/shared/Clock.luau` references `os.clock`, `os.time`,
  `tick`, `DateTime.now` or `task.wait`, and no module other than
  `src/shared/Rng.luau` references `math.random`, `math.randomseed` or
  `Random.new`.
  *Control:* a `__probe_` module placed under `src/shared/` containing a bare
  `os.clock()` call **must** make this test fail and **must** be named in the
  failure. A guard that scans a list it built wrongly passes over everything.
- **AC-6** — AC-5's file list comes from `scripts/classify.sh`, not from a private
  glob or regex in the test. Given a source file created and not yet committed,
  when the guard runs, then that file is in the scanned set.

## Contract

### `src/shared/Clock.luau`

    export type Clock = { now: () -> number }

    export type ManualClock = Clock & {
        advance: (self: ManualClock, deltaSeconds: number) -> (),
        set:     (self: ManualClock, seconds: number) -> (),
    }

    Clock.manual(startSeconds: number) -> ManualClock
    Clock.real() -> Clock

**Semantics of the numbers.** `now()` returns **seconds** as a floating-point
number, monotonic, with no defined epoch — it is a duration since an arbitrary
start, never a wall-clock date. `advance(d)` requires `d >= 0`; a negative delta
is an error, because time going backwards in the phase machine is a defect and
silently clamping it hides the defect. `set` exists for test setup only and may
move backwards.

`Clock.real()` is the **only** function in `src/` permitted to call a real time
source. It is an adapter with no logic; everything that needs the time takes a
`Clock`.

### `src/shared/Rng.luau`

    export type Rng = {
        nextInteger: (self: Rng, min: number, max: number) -> number,
        nextNumber:  (self: Rng) -> number,
        shuffle:     <T>(self: Rng, list: {T}) -> {T},
        derive:      (self: Rng, label: string) -> Rng,
    }

    Rng.fromSeed(seed: number) -> Rng

**Semantics.** `nextInteger(min, max)` is **inclusive at both ends**; `min > max`
is an error rather than an empty range. `nextNumber()` is in `[0, 1)`. `shuffle`
**returns a new list and never mutates its argument** — a shuffle that mutates in
place turns a pure function that takes a seat order into one that corrupts its
caller's state, which is a class of bug that will not show up until SEAT-001.

`derive(label)` returns an **independent sub-stream**: deterministic in
`(parent seed, label)`, and consuming from one sub-stream never perturbs another.
It is what makes adding a consumer of randomness an additive change. Without it,
inserting one `nextInteger` call anywhere shifts every downstream draw, every
recorded round seed stops reproducing its instance, and every seeded test in the
project has to be re-baselined. Sub-stream labels in use so far: `"seats"`
(SEAT-001) and, later, `"instance"` (M3's generator).

`Rng` is the only module permitted to touch `math.random`, `math.randomseed` or
`Random.new`.

### `src/shared/__probe_clock_leak.luau` — the negative control for AC-5

A deliberately offending module written under the **real** path, per
`rules.md`. `paths.conf` classifies `**/__probe_*.*` as `test`, so RED may write
it and every tree-scanning guard skips it by the same rule the phase lock uses.
Do not put it in a temp directory: a probe scanned from somewhere else is scanned
under the wrong path rules, and the guard silently stops testing anything while
still passing.

The guard test must therefore **temporarily include** probe files when running its
control — `scripts/classify.sh --only test` is what tells the two apart — and
exclude them in the normal assertion. Say in the test which is which.

### Test-only dependencies

None. Reading a process's output (`scripts/classify.sh`) is `@lune/process`, which
ships with Lune. If a Lune assertion library turns out to be wanted, it goes in
`wally.toml`'s `[dev-dependencies]` block, which RED may write.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-4 | **Mechanical** | Pin exactly. Arithmetic and a permutation check; nothing to invent. |
| AC-2, AC-3 | **Mechanical, with mandatory controls** | The controls are written above. Implement them literally — a seeded-RNG test that a constant would pass is the most common vacuous test there is. |
| AC-5, AC-6 | **Oracle-free** | You are inventing the guard. Make the probe fire hard and make the failure message name the offending file. Assert the *size* of the scanned set too — a guard over zero files passes. |

## Deferred verifications

<!-- Nothing is deferred, so this section is empty by the template's own rule:
     "REQUIRED when a verification this story depends on provably cannot run in
     the phase that wants it; omit the section otherwise."

     Every control here ran in RED. `Clock`, `Rng` and the probe module are all
     written by this story, and the controls exercise deliberately-wrong fakes
     rather than the missing modules - so none of them needed production code to
     exist, and none was promised rather than measured. The measured values are
     in `## Handoff`, and GREEN re-confirmed every one against the shipped
     modules.

     This was prose rather than a comment until GATES, which made
     check-boundaries.sh read it as a deferred entry with no owner and no
     result. Saying "None" in a section whose contract is "omit when empty" is
     the same defect as a WAIVED with no reason. -->


## Model guidance

**Resolved model of every dispatch, by name:** _(to be recorded at dispatch — the
`test-developer` and `feature-developer` definitions both declare `model: opus`;
record what actually resolved, and ask each subagent to say whether it was
dispatched with an override.)_

The oracle partition above is the part of this brief that matters most. AC-5 and
AC-6 are the oracle-free pair, and the measured finding in `story-authoring` is
that the partition does more for control quality than the model choice does.

**Success condition for this story's RED:** the AC-2, AC-3 and AC-5 controls each
fail against a plausible wrong implementation, demonstrated in the handoff — not
merely described. If any control cannot be made to fail, that control is wrong and
the criterion is not ready.

## Out of scope

- The phase machine. This story builds the two primitives it will be injected
  with, nothing else.
- Any use of `Clock.real()` anywhere. It is written and then not called until a
  driver exists.
- A `--!strict` header guard. Real behaviour, its own story, not folded in here
  because it is adjacent.
- Cryptographic quality of `Rng`. This is a game seed, not a security primitive.
  Reproducibility and independence are the requirements; unpredictability is not.

## Notes

**Mutation the orchestrator should run at acceptance**, against the committed
implementation, via `bash scripts/mutate.sh`:

1. In `Rng.luau`, make `derive` return `self`. Predicted: AC-3's independence
   assertion goes red and the same-label assertion stays green — exactly one
   assertion, which is where a vacuous test would hide.
2. In `Clock.luau`, make `advance` ignore its argument. Predicted: AC-1 goes red.
3. In `Rng.luau`, make `shuffle` mutate in place and return the same table.
   Predicted: AC-4's "input not mutated" assertion goes red and the permutation
   assertion stays green.

Record the observed counts against these predictions here. Mutation 1 is the one
to run first: it is the assertion most likely to have been written vacuously.

**Raise the `unit` floor** in `project.conf` as part of this story, to the real
count this suite produces. With `coverage` unconfigured (`stack.md` §4) the floor
is the only automated thing standing between this project and a suite that
quietly shrinks.

RED measured the count: `lune run test -- --list` reports **50 tests**, and all 50
must pass once GREEN lands, so the line becomes `floor | unit | 50`. RED did not
make that edit — `project.conf` is the Lead PO's file per `rules.md`, and a floor
raised before the suite is green would be a floor nobody has seen satisfied.

`covers | unit | src/shared/**` already reads both modules this story adds, so no
`covers` line changes.

## Test plan

Levels, chosen for what can actually falsify each criterion:

| AC | Level | Where |
|---|---|---|
| AC-1 | unit, against a manual clock | `tests/shared/clock_test.luau` |
| AC-2, AC-3, AC-4 | unit, against `Rng.fromSeed` | `tests/shared/rng_test.luau` |
| AC-5, AC-6 | integration with the harness — it shells out to `scripts/classify.sh` and reads the real tree | `tests/shared/source_guard_test.luau` |

The criteria themselves are written **once**, as checks over a *factory*
(`tests/helpers/ClockContract.luau`, `tests/helpers/RngContract.luau`), and
applied twice: to the real module, and to deliberately wrong implementations in
`tests/helpers/Fakes.luau`. That shape is the answer to the specific hazard
`rules.md` names — **in RED the module under test does not exist, the file dies at
`require`, and not one assertion in it has run**, so every control in it is
unverified for the whole phase. Applying the same check objects to known-wrong
implementations in a file that requires no production code means the AC-2, AC-3,
AC-4 and AC-1 assertions have each been **observed rejecting something** during
RED, not merely written.

Two consequences worth stating:

- `clock_test.luau` and `rng_test.luau` `pcall` their module at the top and
  re-assert inside every test. Without it the runner reports one `LOAD FAIL` for
  a whole file — one line of red covering seven criteria. It is not a skip:
  every test still fails, naming the module that did not load.
- `Fakes.correct` is a working seeded generator, and it is there to make each
  control **specific**: every wrong implementation is that baseline with exactly
  one thing broken, and the control asserts the matching check goes red while
  the others stay green. It is not a specification of the algorithm — no test in
  this story pins a number stream.

The guard (AC-5, AC-6) asks `bash scripts/classify.sh --list source src` and
scans **every path it returns, whatever the extension**. No glob, no directory
walk, no path regex, per `rules.md`. It strips comments and string literals
before matching, which is load-bearing rather than tidy: `src/shared/Scaffold.luau`
names `os.clock`, `tick`, `task.wait`, `math.random` and `Random.new` in a doc
comment explaining that nothing may call them, so a line-grep guard's first act
would be to fail on the file documenting the rule.

## Handoff: RED -> GREEN

### The command

```
lune run test
```

(`bash scripts/task.sh test` is the same thing. The unit gate is `lune run test`;
`bash scripts/gates.sh --fast` runs it alongside format, lint, typecheck, build.)

### The failure, verbatim

Below is `lune run test` with the 26 `pass` lines stripped. Nothing else is
edited; the repeated two-line message under the `clock_test` and `rng_test`
entries is what the runner actually printed for each.

```
  FAIL  tests/shared/clock_test.luau :: AC-1: a manual clock advances by exactly the deltas it is given
        C:\Users\ryanc\Projects\first-roblox\tests\shared\clock_test:20: src/shared/Clock.luau did not load: error requiring module "../../src/shared/Clock": could not resolve child component "Clock"
  FAIL  tests/shared/clock_test.luau :: AC-1: advancing a manual clock by zero changes nothing
  FAIL  tests/shared/clock_test.luau :: Contract: Clock.manual and Clock.real are both exported functions
  FAIL  tests/shared/clock_test.luau :: Contract: Clock.real returns a clock whose now is a number that never goes backwards
  FAIL  tests/shared/clock_test.luau :: Contract: a manual clock refuses a negative advance
  FAIL  tests/shared/clock_test.luau :: Contract: a manual clock satisfies the plain Clock interface
  FAIL  tests/shared/clock_test.luau :: Contract: set moves a manual clock backwards
        [each of the six above carries the identical clock_test:20 message]
  FAIL  tests/shared/rng_test.luau :: AC-2: two Rngs from different seeds produce different sequences
        C:\Users\ryanc\Projects\first-roblox\tests\shared\rng_test:26: src/shared/Rng.luau did not load: error requiring module "../../src/shared/Rng": could not resolve child component "Rng"
  FAIL  tests/shared/rng_test.luau :: AC-2: two Rngs from the same seed produce identical sequences
  FAIL  tests/shared/rng_test.luau :: AC-3: draining one derived sub-stream does not change another
  FAIL  tests/shared/rng_test.luau :: AC-3: the same derive label on two same-seeded parents gives the same sub-stream
  FAIL  tests/shared/rng_test.luau :: AC-4: shuffle does not mutate the list it was given
  FAIL  tests/shared/rng_test.luau :: AC-4: shuffle does not return the input order for every seed
  FAIL  tests/shared/rng_test.luau :: AC-4: shuffle handles an empty list and a single-item list
  FAIL  tests/shared/rng_test.luau :: AC-4: shuffle returns a permutation of its input
  FAIL  tests/shared/rng_test.luau :: Contract: a derived sub-stream is itself an Rng that can derive again
  FAIL  tests/shared/rng_test.luau :: Contract: derive is deterministic in the label, not only in the parent seed
  FAIL  tests/shared/rng_test.luau :: Contract: fromSeed is exported and returns the whole Rng interface
  FAIL  tests/shared/rng_test.luau :: Contract: nextInteger is inclusive at both ends
  FAIL  tests/shared/rng_test.luau :: Contract: nextInteger stays inside a wide range and accepts a negative one
  FAIL  tests/shared/rng_test.luau :: Contract: nextInteger with min equal to max returns that value
  FAIL  tests/shared/rng_test.luau :: Contract: nextInteger with min greater than max is an error
  FAIL  tests/shared/rng_test.luau :: Contract: nextNumber is in [0, 1)
        [each of the sixteen above carries the identical rng_test:26 message]
  FAIL  tests/shared/source_guard_test.luau :: AC-5: the scanned set is the real source tree, including this story's two adapters
        C:\Users\ryanc\Projects\first-roblox\tests\shared\source_guard_test:78: src/shared/Clock.luau is not in the scanned set: src/client/.gitkeep, src/net/.gitkeep, src/server/.gitkeep, src/shared/Scaffold.luau
26 passed, 24 failed
```

`bash scripts/gates.sh --fast`, same tree, is the right shape for RED — the
static gates are green and only the test gate is red:

```
--- gate summary ---
PASS         format (1s, observed 3)
PASS         lint (1s, observed 3, floor 1)
PASS         typecheck (3s, observed 1)
FAIL         unit (6s, exit 1) -> .claude/state/gate-logs/unit.log
UNCONFIGURED coverage
PASS         build (0s, observed 2917)

--fast skipped: integration mutation
1 required gate(s) failed.
```

Two notes on those numbers. The `observed` counts come from `git ls-files`, and
the new files were untracked at that moment; they rise once committed — the
tools themselves already walked the directories, so the probe module is linted,
formatted and analysed in that run. And the unit gate was **14 s** before the
classifier result was cached; see "What the guard costs".

### What each test asserts, and which AC it covers

`tests/shared/clock_test.luau` — all fail on the missing module:

| Test | Asserts | AC |
|---|---|---|
| a manual clock advances by exactly the deltas it is given | 100 → advance(5) → 105 → advance(2.5) → 107.5, and `now()` is stable on repeated calls between advances | AC-1 |
| advancing a manual clock by zero changes nothing | the zero edge: `advance(0)` is not an error and moves nothing | AC-1 |
| a manual clock refuses a negative advance | `advance(-1)` errors and leaves `now()` where it was | Contract |
| set moves a manual clock backwards | `set(4)` after advancing, then `advance(1)` → 5 | Contract |
| Clock.manual and Clock.real are both exported functions | the module's two exports exist | Contract |
| Clock.real returns a clock whose now is a number that never goes backwards | the real adapter is a `Clock`; two reads, both numbers, non-decreasing | Contract |
| a manual clock satisfies the plain Clock interface | `now`, `advance`, `set` are functions and `clock.now()` (dot, no self) returns the start value | Contract |

`tests/shared/rng_test.luau` — all fail on the missing module:

| Test | Asserts | AC |
|---|---|---|
| two Rngs from the same seed produce identical sequences | seeds 1, 7, 20260915: identical `nextInteger`/`nextNumber`/`shuffle` sequences | AC-2 |
| two Rngs from different seeds produce different sequences | seed pairs (1,2), (7,8), (0,1), (1234,5678) all diverge | AC-2 |
| the same derive label on two same-seeded parents gives the same sub-stream | `derive("seats")` and `derive("instance")` reproduce across two seed-4242 parents | AC-3 |
| draining one derived sub-stream does not change another | 50 draws from `derive("a")` leave `derive("b")` identical, **and the reverse** | AC-3 |
| derive is deterministic in the label, not only in the parent seed | `derive("seats")` ≠ `derive("instance")` from the same seed | Contract |
| a derived sub-stream is itself an Rng that can derive again | a child has all four methods and a grandchild is reproducible | Contract |
| shuffle returns a permutation of its input | same multiset, same length, nothing invented | AC-4 |
| shuffle does not mutate the list it was given | the input is unchanged **and** the result is not the caller's table | AC-4 |
| shuffle handles an empty list and a single-item list | empty, one — neither errors, neither returns the input table | AC-4 |
| shuffle does not return the input order for every seed | across 20 seeds at least one order differs (a copy-only shuffle satisfies every word of AC-4) | beyond AC-4 |
| nextInteger is inclusive at both ends | `nextInteger(1, 2)` over 200 draws yields both 1 and 2 and nothing else | Contract |
| nextInteger stays inside a wide range and accepts a negative one | `nextInteger(-5, 5)` is an integer inside the range | Contract |
| nextInteger with min equal to max returns that value | `nextInteger(7, 7) == 7` | Contract |
| nextInteger with min greater than max is an error | `nextInteger(5, 1)` errors rather than returning nothing | Contract |
| nextNumber is in [0, 1) | 200 draws, `0 <= v < 1` | Contract |
| fromSeed is exported and returns the whole Rng interface | `Rng.fromSeed` exists; the instance has all four methods | Contract |

`tests/shared/source_guard_test.luau` — one fails now, the rest are discussed
under "Tests that pass on arrival":

| Test | Asserts | AC |
|---|---|---|
| no source module outside the Clock adapter reads a real time source | zero `os.clock`/`os.time`/`tick`/`DateTime.now`/`task.wait` references across the classified source set | AC-5 |
| no source module outside the Rng adapter reads a real random source | zero `math.random`/`math.randomseed`/`Random.new` references | AC-5 |
| **the scanned set is the real source tree, including this story's two adapters** | ≥ 4 files scanned, and `Clock.luau` and `Rng.luau` are both in the set — **this is the AC-5 test that is red now**, and it is the size assertion the oracle partition demanded, in a form no four files can satisfy | AC-5 |
| the probe module's os.clock call is found and named in the failure | with probes added to the list, exactly the probe is reported, by path, with `os.clock` | AC-5 control |
| a source file created and not yet committed is in the scanned set | writes a fixture under `src/shared/`, lists, removes, asserts it was listed | AC-6 |
| the scanned set excludes probe artifacts and still contains real modules | the probe is absent from `source` and present in `test`, and the source set still holds a real `.luau` module (an over-broad exclusion is the same defect reversed) | AC-6 |
| the guard does not fire on a symbol named in a comment / in a string literal | comments and strings are blanked before matching | AC-5 (scanner) |
| the guard fires on a real call, and reports its line | one finding, right symbol, right line | AC-5 (scanner) |
| the guard fires on a call written inside a string interpolation | backtick `{...}` holes are code | AC-5 (scanner) |
| the guard does not fire on identifiers that merely contain a symbol | `ticket`, `ticking`, `self.tick`, `{ tick = 2 }` are not the global | AC-5 (scanner) |
| the guard fires on a symbol that is read without being called | `local grab = tick` and `os.clock ~= nil` still count — the exclusion above is not too broad | AC-5 (scanner) |
| the guard fires on a bare tick() call | word-boundary match on a bare global | AC-5 (scanner) |
| the guard counts math.randomseed once, as itself | not a `math.random` hit plus a `math.randomseed` hit | AC-5 (scanner) |
| each adapter may say its own symbols and not the other's | `Clock.luau` may call `os.clock` and not `math.random`; `Rng.luau` the reverse | AC-5 |

`tests/shared/clock_controls_test.luau` and `tests/shared/rng_controls_test.luau`
are the controls; see the table below.

### The export shape these tests already pin

Stated as fact, not suggestion — a test imports each of these and a wrong guess
is a failure, not a debate.

**`src/shared/Clock.luau`**, required as `require("../../src/shared/Clock")` from
`tests/shared/`, returns a table with:

- `Clock.manual(startSeconds: number) -> ManualClock` — called with a **dot**.
- `Clock.real() -> Clock` — called with a **dot**, takes no arguments.
- On the returned manual clock: **`clock.now()` is called with a dot and takes no
  `self`.** `clock:advance(delta)` and `clock:set(seconds)` are called with a
  **colon**. That mix is the story's Contract verbatim and the tests call it
  exactly that way; `now` defined as a method will fail with a `nil`/arity error.
- `advance(-1)` must raise (the test only requires `pcall` to return false — the
  message is yours) and must not move the clock.
- `Clock.real().now()` must return a `number` and must not decrease between two
  consecutive calls.

**`src/shared/Rng.luau`**, required as `require("../../src/shared/Rng")`:

- `Rng.fromSeed(seed: number) -> Rng` — called with a **dot**.
- On the instance, all four are called with a **colon**: `rng:nextInteger(min, max)`,
  `rng:nextNumber()`, `rng:shuffle(list)`, `rng:derive(label)`.
- `derive` returns an object exposing all four of those, and a derived stream must
  itself be derivable and reproducible.
- `shuffle` must return a table that is **not** `rawequal` to its argument, for
  every input **including the empty list**.
- `nextInteger(5, 1)` must raise.
- Seeds used by the tests include `0`, so `fromSeed(0)` must work.

**Not constrained, and deliberately yours:** the generator algorithm, any
particular number stream (there are no golden values anywhere in this story), how
`derive` mixes the label into a child seed, whether instances are closures or a
metatable class, and every error message text. `export type Clock`, `ManualClock`
and `Rng` are Contract obligations that **no test checks** — `luau-lsp analyze`
runs over `src` only, so the types are judged by the typecheck gate and not here.

### Tests that passed on arrival, and what earns them

Three groups. Each is earned by a mutation run through `bash scripts/mutate.sh`,
which restored the file and verified the restore byte-for-byte.

**1. AC-5's two "no source module references…" assertions.** They are green on an
honest tree, which is exactly the vacuous shape `rules.md` warns about. Earned by
making a real source module leak:

```
$ bash scripts/mutate.sh src/shared/Scaffold.luau \
    's/^local Scaffold = {}$/local Scaffold = { startedAt = os.clock() }/' -- lune run test

=== mutate: src/shared/Scaffold.luau (1 line(s) changed) ===
  20 - local Scaffold = {}
  20 + local Scaffold = { startedAt = os.clock() }

  FAIL  tests/shared/source_guard_test.luau :: AC-5: no source module outside the Clock adapter reads a real time source
        tests\shared\source_guard_test:55: 1 time-source reference(s) outside src/shared/Clock.luau, over 4 scanned file(s):
src/shared/Scaffold.luau:20 references os.clock - only src/shared/Clock.luau may
25 passed, 25 failed

=== mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_shared_Scaffold.luau.20260915T193051Z.1654959.bak) ===
  20: local Scaffold = {}
```

Exactly one test flipped (26/24 → 25/25): the time assertion went red naming the
file and line, and the random assertion stayed green.

**2. AC-6's "uncommitted file is in the scanned set".** Earned by replacing the
classifier with the wrong list — the git index, which is the mistake the criterion
exists to forbid:

```
$ bash scripts/mutate.sh tests/helpers/SourceScan.luau \
    's|process.exec("bash", { "scripts/classify.sh", "--list", category, "src" })|process.exec("git", { "ls-files", "src" })|' \
    -- lune run test

  70 - 	local result = process.exec("bash", { "scripts/classify.sh", "--list", category, "src" })
  70 + 	local result = process.exec("git", { "ls-files", "src" })

  FAIL  tests/shared/source_guard_test.luau :: AC-6: a source file created and not yet committed is in the scanned set
        tests\shared\source_guard_test:140: src/shared/__ac6_uncommitted_fixture.luau was written and not committed, and the guard did not see it. A list built from the git index, or from a glob over committed files, fails exactly here. The guard saw: src/client/.gitkeep, src/net/.gitkeep, src/server/.gitkeep, src/shared/Scaffold.luau
24 passed, 26 failed

=== mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/tests_helpers_SourceScan.luau.20260915T193126Z.1657280.bak) ===
```

Two tests flipped: AC-6's uncommitted check, and the AC-5 control (an untracked
probe is invisible to `git ls-files` too). Both are the right answer.

**3. The scanner's own discrimination tests and the control suites.** These assert
over test code and synthetic text, so they are green from the moment they are
written. They are earned structurally rather than by mutation: each is a
two-directional pair — a case that must fire and a case that must not — and the
control suites assert that `Fakes.correct` passes every check before asserting
that each broken fake fails exactly one. A check that had stopped discriminating
would fail the "must fire" half of its own pair.

### Negative controls: expected values GREEN must confirm

Every control in this story **ran in RED** — that is why they live in files that
require no production code. The numbers below are measured, not predicted. What
GREEN owes is the other half: confirm that the *real* `Clock` and `Rng` land on
the "passes" side of every row.

| Control | Check it must PASS | Check it must FAIL | Measured in RED |
|---|---|---|---|
| `Fakes.correct` (baseline) | all 8 Rng checks | — | 8 PASS, 0 FAIL |
| `Fakes.seedIgnoring` (AC-2) | `sameSeedReproduces` | `differentSeedsDiverge` | PASS / FAIL — "AC-2: seeds 1 and 2 produced the same sequence, so the seed is not being used" |
| `Fakes.selfDeriving` (AC-3) | `sameLabelSameSubStream` | `deriveIsIndependent` | PASS / FAIL — "AC-3: 50 draws from derive(\"a\") changed derive(\"b\") at draw **1**" |
| `Fakes.labelIgnoringDerive` (Contract) | `sameLabelSameSubStream` **and** `deriveIsIndependent` | `differentLabelsDiffer` | PASS, PASS / FAIL — "derive(\"seats\") and derive(\"instance\") from seed 77 are the same stream" |
| `Fakes.mutatingShuffle` (AC-4) | `shuffleIsAPermutation` | `shuffleDoesNotMutateItsInput` | PASS / FAIL — "shuffle mutated its argument: a,b,…,j -> d,c,j,i,g,b,f,e,h,a" |
| `Fakes.frozenClock` (AC-1) | `zeroAdvanceChangesNothing` | `advanceMovesNowByTheDelta` | PASS / FAIL — "after advance(5) from 100, now() is **100**, wanted **105**" |
| `Fakes.clampingClock` (Contract) | `advanceMovesNowByTheDelta` | `negativeAdvanceIsAnError` | PASS / FAIL — "advance(-1) was accepted; now() is 10" |

The AC-5 scan, measured on the tree as it stands:

| Quantity | Measured |
|---|---|
| files returned by `classify.sh --list source src` | **4** (`src/client/.gitkeep`, `src/net/.gitkeep`, `src/server/.gitkeep`, `src/shared/Scaffold.luau`) |
| files returned by `classify.sh --list test src` | **1** (`src/shared/__probe_clock_leak.luau`) |
| findings over the source set alone | **0** |
| findings over source + probes | **1** — `src/shared/__probe_clock_leak.luau:28 references os.clock - only src/shared/Clock.luau may` |

After GREEN the source set becomes **6** and the findings over the source set must
stay **0** — with `Clock.luau` allowed `os.clock` and `Rng.luau` allowed
`math.random` by ownership, not by exception.

### Deferred verifications

The story records **None**, and RED confirms it: every control here was runnable
without production code and every one was run. Nothing is deferred to GREEN except
confirming the measured values above against the shipped modules.

### Files written

- `tests/helpers/SourceScan.luau` — the classifier-backed scanner (new)
- `tests/helpers/ClockContract.luau` — AC-1 and Clock Contract checks (new)
- `tests/helpers/RngContract.luau` — AC-2/3/4 and Rng Contract checks (new)
- `tests/helpers/Fakes.luau` — the wrong implementations behind the controls (new)
- `tests/shared/clock_test.luau` (new)
- `tests/shared/rng_test.luau` (new)
- `tests/shared/clock_controls_test.luau` (new)
- `tests/shared/rng_controls_test.luau` (new)
- `tests/shared/source_guard_test.luau` (new)
- `src/shared/__probe_clock_leak.luau` — AC-5's probe. Under `src/` on purpose,
  classified `test` by `paths.conf`, owned by `source_guard_test.luau` (new)
- this story's `## Test plan` and `## Handoff` sections

No manifest change: `wally.toml` is untouched, because nothing here needs a
dependency Lune does not ship.

### What GREEN should know before starting

- **`shuffle` must copy even when the list is empty.** The empty/singleton test
  asserts `rawequal(result, input) == false`, and an early `if #list == 0 then
  return list end` fails it.
- **`derive` must mix the label in, not only the seed.** Two checks constrain it
  from opposite sides: sub-streams must be independent (so `derive` cannot return
  `self` or share state), and different labels must give different streams (so it
  cannot ignore the label). A child seed derived from `(parent seed, label)` with
  the parent's own state untouched satisfies both. Note that `derive` must **not**
  consume from the parent: `deriveIsIndependent` derives `"a"` and `"b"` from the
  same parent in the same order in both runs, so consuming would be legal — but
  `sameLabelSameSubStream` derives one label from a fresh parent each time, so a
  `derive` that consumes parent state is fine there too. It is `differentLabelsDiffer`
  plus independence that force the mixing.
- **`nextInteger` is inclusive at the top and the test will catch a floating-point
  off-by-one.** `min + floor(nextNumber() * (max - min + 1))` needs `nextNumber()`
  to be strictly below 1, which the `[0, 1)` test pins separately.
- **The guard reads every file the classifier returns, including `.gitkeep`.** If
  a later story puts a binary under `src/`, `fs.readFile` will be handed bytes.
  That is a real limit and it is not worked around by catching the error — if it
  happens, the fix is a decision about what belongs in `src/`, not a `pcall`.
- **What the guard costs.** `classify.sh` is a `bash` process and costs about a
  second on Windows; eight calls made the unit gate 14 s. `SourceScan` now caches
  one answer per category per run, and the suite is **4.6 s** locally (Windows,
  warm; CI is Linux and cheaper per spawn). The cache has one rule, written at the
  function: a test that changes the tree must call `SourceScan.refresh()` after
  writing **and** after removing. `source_guard_test.luau` is the only such test.
- **Do not delete `src/shared/__probe_clock_leak.luau`.** The AC-5 control asserts
  it is present and classified `test`; removing it fails the control, which is
  the intended coupling.
- **`src/shared/Scaffold.luau` may be deleted** by a later story without breaking
  anything here — no test names it. The AC-5 size assertion names `Clock.luau` and
  `Rng.luau` instead.

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-15T20:04:45Z
    commit: 67a1e75
    tree:   189b6059f13db48772fdad59ac8e25417ee1230f
    result: pass (5 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 15)
    PASS         lint (1s, observed 15, floor 1)
    PASS         typecheck (2s, observed 4)
    PASS         unit (6s, observed 50, floor 50)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 6691)
    UNCONFIGURED mutation

