---
id: ROUND-001
title: Clock and randomness are injected, and nothing else may read them
slug: clock-and-randomness-are-injected-and-no
epic: EPIC-01
type: feature
status: todo
phase: PLANNED
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

None. Every control here can be run in RED: `Clock`, `Rng` and the probe module
are all written by this story, and a hand-written vacuous implementation is enough
to fire each control without any production code existing.

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
