---
id: HARNESS-011
title: A contract helper's failure message survives past 511 characters
slug: a-contract-helper-s-failure-message-surv
epic: 
type: chore
status: todo
phase: PLANNED
branch: story/HARNESS-011-a-contract-helper-s-failure-message-surv
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Two things, one cause: `assert` is the wrong primitive for a contract check.

**A documented constant is off by one.** `docs/wiki/stack.md:230` records
"An `assert` message is truncated at 512 characters". The true figure is **511**.

**Seven contract checks are being truncated at 511 today, in a green suite.**
`tests/helpers/RingContract.luau` builds failure messages longer than the cap for
seven of its checks. Whatever those messages meant to say past character 511 is
gone before anyone reads them.

### Part A — the cap is 511, not 512

Measured on Lune 0.10.5, this machine, by placing a distinct marker at a known
1-based index inside a 2000-character message and raising it through
`pcall(function() assert(false, msg) end)`:

    marker at index 511   survives = true
    marker at index 512   survives = false
    prefix length: 175    kept chars from a 2000-char message: 511

**`ROUND-004`'s own table already supported 511 and was read as 512.** It is
self-inconsistent on its face: it reports a 400-character message keeping
"401 A's", which is impossible. That derived column is +1 throughout. Its *raw*
numbers are correct and give the right answer directly — a 400-char message
produced `err` of 444, so the prefix is 44 characters; the capped `err` is 555;
`555 - 44 = 511`.

**`stack.md` is CORRECT that the position prefix is not counted against the cap,
and that sentence must survive this story.** Verified by running the identical
probe from directories whose names were 1, 40 and 90 characters long:

    dir name length    prefix    max surviving message length
    1                  173       511
    40                 212       511
    90                 259       511

The prefix moves; the cap does not. So the cap is on the message alone and is
machine-independent — there is no local-vs-CI divergence hiding here. Fix only
the number, and add a line recording the off-by-one and this correction, so that
a future reader with `ROUND-004`'s derived column in hand does not "re-correct"
511 back to 512.

### Part B — the truncation is destroying evidence now

*Measured at filing, before SEAT-002 and SEAT-003 landed, and not re-taken at
PLANNED. SEAT-003 has since grown `ring_controls_test.luau` and routed its own
new checks through a private `check`, so the figures below describe the
SEAT-001 checks, which still raise through bare `assert`.*

Every `names(message, fragment, what)` call site was instrumented via
`scripts/mutate.sh` — 55 of them, across the three relevant controls tests
(`tests/server/ring_controls_test.luau` 32, `tests/server/round_ending_controls_test.luau` 16,
`tests/server/lobby_gate_controls_test.luau` 7) — and the message body measured
after stripping the 109-character path prefix:

| Helper | Measured body length |
|---|---|
| `tests/helpers/RingContract.luau` | exactly **511 (truncated)** for SEAT-001's AC-1, AC-2, AC-3, AC-4, AC-5, AC-7 and the sub-stream pin — seven checks |
| `tests/helpers/LobbyGateContract.luau` | max 404 — not truncated |
| `tests/helpers/RoundEndingContract.luau` | max 291 — not truncated |

Throughout `## Context`, an `AC-N` names a **SEAT-001** criterion as implemented
in `RingContract.luau` — never one of this story's own, which are numbered
independently under `## Acceptance criteria` below. The two sets collide by
number and mean different things.

### What is NOT wrong here

**There is no vacuous assertion, and this story must not claim one.** `names()`
asserts a needle is **present**, so a needle pushed past the cap makes the test
**fail loudly**, not pass. The suite is green at **443 passed, 0 failed**
(197 at filing), which is itself proof that every needle currently matches.

The shape that *would* pass vacuously is an assertion that a needle is **absent**
— `rules.md`'s "a lockfile is permitted unchecked" case. A search found the only
absence-shaped assertions in the tree are on nil **values**
(`tests/server/phase_machine_test.luau:228`, `tests/shared/rng_test.luau:75`),
not on message content. No helper greps an error message internally. The other
two pcall-and-inspect sites (`tests/server/lobby_gate_test.luau:216`,
`tests/server/phase_machine_test.luau:724`) count violations and embed messages
rather than grepping for needles.

**Consequently this story carries no "earn the assertion by mutation" obligation
of the `rules.md` kind for an unreachable needle, because no needle is
unreachable — there is nothing to watch go red on that axis. Do not invent one.**
(This does not exempt the story from the general rule; see `## Notes`.)

What *is* real is a fragility worth recording. The needle belonging to
**SEAT-001's** AC-5 — the distribution check in `RingContract.luau`, not this
story's own AC-5 —

    kim>zed,zed>amy,amy>bob,bob>kim = 10000 (100.0%)  <- above 25.0%

— ends at body offset **479 of 511**. Thirty-two characters of slack. Any
widening of that message loses it, and the failure mode is a red suite.

### The required gate that would fail if this story's artifact broke

`unit` (`lune run test`), which is `required` in `project.conf` and where the
contract helpers run. `required_gates` stays empty: there is no optional gate to
promote. Note that `covers` lines in `project.conf` name `src/**` only, so the
covers check does not apply to a test-only change; `unit` still runs the suite.

## Acceptance criteria

<!-- Frozen once this story leaves PLANNED. A change goes in ## Amendments. -->

- **AC-1** — Given a contract failure message longer than 511 characters, when a
  contract check raises it, then the message arrives at the caller **intact** —
  every character present, in order.
  *Control:* the **same** message raised through bare `assert` must fail this
  assertion, cut at exactly 511 characters. That control is what makes the
  criterion mean something, and it can be written, because the truncation is real
  and reproducible today (`## Context`, Part A).

- **AC-2** — Given a contract check that **passes**, when it runs, then its
  failure message is never built.
  *Control:* a message-builder that increments a counter shows **zero**
  increments across a passing run, and a non-zero count on a failing one. (The
  non-zero half is required: a counter that never increments at all satisfies the
  zero-case for the wrong reason.)

- **AC-3** — Given `docs/wiki/stack.md`, then it records the cap as **511**,
  retains the sentence stating that the position prefix is *not* counted against
  the cap, and carries a line recording that the previously documented 512 was an
  off-by-one derived from `ROUND-004`'s table.

- **AC-4** — Given the four in-scope helpers (`RingContract.luau`,
  `LobbyGateContract.luau`, `RoundEndingContract.luau`,
  `ProjectionContract.luau`), then **no** call to bare `assert` and **no**
  helper-private raiser (a local `check` wrapper, or a direct `error(` call)
  remains in any of them: every failure is raised through the shared raiser.
  The file enumeration is obtained from `bash scripts/classify.sh`, never from a
  private regex — `rules.md` is explicit that a guard asks for that answer rather
  than reimplementing it, and names four drifting private copies as the cost.
  *Control:* a single site reintroduced to bare `assert` must be reported by
  **name and line**, not merely counted; so must a single reintroduced direct
  `error(` call. A count-only assertion passes while pointing at nothing.
  *Scope note, so this criterion is not read wider than it is:* every other
  helper that raises — see `## Out of scope` for the list — is deliberately
  **not** in AC-4's set.

- **AC-5** — Given the full suite, when it runs after this change, then it
  reports **`0 failed`**. That number is the whole of this criterion: one
  integer, read from the runner's own final line, with no arithmetic.
  *Why that is not vacuous:* `0 failed` is also what a suite that shrank to
  nothing reports. The count is held up from below by the already-configured
  `floor | unit | 443` in `.claude/harness/project.conf` — 443 being the passing
  count before this story (re-measured at PLANNED, 2026-09-28, after SEAT-002
  and SEAT-003 landed; it was 197 when the story was filed). A floor is a
  minimum, so the tests this story adds raise the total and require no edit to it.
  *Control:* reverting any single converted call site to bare `assert` must make
  this number non-zero, via AC-4's guard. A criterion that stays at `0 failed`
  through that revert is checking nothing.

## Contract

<!-- Amendable by SCAFFOLD in place, with a reason. -->

### The raiser

A **shared** raiser in a test helper, exported as `Contract.fail(msg: string): never`
(or the nearest thing Luau's checker accepts for a function that always raises),
implemented with **`error(msg, 0)`**.

Measured, so that the choice of `0` is not taste:

| Call | Result on a 900-character message |
|---|---|
| `error(msg, 0)` | all 900 characters, **no** prefix |
| `error(msg, 1)` | all 900 characters **with** a position prefix (total 1075) |
| `error(msg, 2)`, real nested caller | all 900 characters **with** a position prefix (total 1075) |

So **truncation belongs to `assert` specifically, not to position-prefixing** —
`error` does not truncate at any level.

**Why level 0 rather than 2.** From inside a contract check, level 2 resolves to
the controls test's `pcall(check, ring)` line, which is less informative than the
message's own `AC-N:` header. Level 0 also drops the 109-character path prefix,
which is dead weight in a message that exists to be grepped.

**Caveat, to be carried into the helper's own comment:** level 0 shifts every
needle offset by **-109**. Harmless for a plain `string.find`, but relevant to
any future **anchored** match — which is `rules.md`'s first and cheapest defence
against a needle that cannot fail. Anyone adding an anchored assertion over these
messages needs to know the prefix is gone.

### The call shape

Every converted site becomes:

    if #violations > 0 then
        Contract.fail(`AC-N: ...{firstFew(violations, 8)}`)
    end

rather than `assert(#violations == 0, <message>)`. This is not cosmetic and it is
the second half of the fix: **Luau evaluates `assert`'s message argument
eagerly**, so `firstFew(violations, 8)` and every `table.concat` in these helpers
runs on every **passing** check. Not theoretical — an instrumented `firstFew`
flooded stdout from passing paths and timed the suite out **twice, at 420s and
600s**. AC-2 pins the fix.

### Scope of conversion

| File | Obligation |
|---|---|
| the shared raiser (new) | required |
| `tests/helpers/RingContract.luau` | required — it is the file that truncates |
| `tests/helpers/LobbyGateContract.luau` | required, for the one-answer reason, though it does not truncate today (max 404) |
| `tests/helpers/RoundEndingContract.luau` | required, same (max 291) |
| `tests/helpers/ProjectionContract.luau` | required — PO-2: brought in at PLANNED once `SEAT-002` was DONE |

Site counts, re-measured at PLANNED on 2026-09-28 (`main` @ `bdc5d61`):

| Helper | bare `assert` | private `check(` calls | direct `error(` | total |
|---|---|---|---|---|
| `RingContract` | 9 (lines 215, 253, 277, 316, 391, 512, 611, 693, 733) | 15 (656, 839, 943, 974, 1045, 1120, 1182, 1231, 1295, 1416, 1522, 1586, 1656, 1742, 1813) | 1 — the body of its private `check` (168) | 24 sites + the wrapper |
| `LobbyGateContract` | 32 | 0 | 0 | 32 |
| `RoundEndingContract` | 64 | 0 | 0 | 64 |
| `ProjectionContract` | 1 (580, fixed message) | 7 (352, 425, 582, 672, 806, 811, 841) | 2 — a fixture precondition (118) and its private `check` body (248) | 9 sites + the wrapper |
| **all four** | | | | **129 sites, 2 private wrappers removed** |

**The four in-scope helpers are not the same shape, and the conversion is not
one find-and-replace.** `RingContract` and `ProjectionContract` accumulate
`violations` and report `firstFew(...)`; `LobbyGateContract` and
`RoundEndingContract` build an interpolated message **at each site**, largely
fixture preconditions (`` `fixture: ...` ``) and per-criterion messages. All
shapes are eagerly evaluated and all belong behind the raiser; the accumulating
shape is the one that reaches 511.

**The private `check` wrappers are eagerly evaluated too.** `SEAT-002` and
`SEAT-003` each added a local `check(condition, message)` → `error(message, 2)`
to escape the truncation. It does escape it, but `message` is still an argument,
so it is built on every passing call exactly as `assert`'s is. Converting them is
PO-1, and it is what AC-2 requires of these files. Their doc comments also quote
the wrong cap ("512 characters after the location prefix"); those comments go
with the wrappers.

**Level 0 changes no needle.** Searched at PLANNED: no test under
`tests/server`, `tests/shared` or `tests/net` matches a position prefix
(`Contract.luau:`, `_test.luau:<n>`), so dropping it from the level-2 sites
does not alter any assertion.

### Phase path: PLANNED → SCAFFOLD → GATES → REVIEW → DONE

**Not RED → GREEN, and the reason is mechanical rather than a preference.** Every
code file this story touches classifies as `test`:

    $ bash scripts/classify.sh tests/helpers/RingContract.luau tests/server/ring_controls_test.luau
    test    tests/helpers/RingContract.luau
    test    tests/server/ring_controls_test.luau

`phases.conf` gives GREEN and GATES `source,config,manifest,docs,harness` — not
`test`. So GREEN could not write a single line of this fix, and the story would
be a RED that does everything followed by a GREEN with nothing to do. `chore` is
the type whose table row says it "may use SCAFFOLD", and this is the case it is
for. The alternative considered and rejected is in `## Notes`.

**SCAFFOLD unlocks the phase but not the discipline.** The ordering obligation
stands and is checkable, because every one of these assertions is genuinely red
against the tree as it stands:

1. Write AC-1's assertion and its `assert` control **first**. Run it. It fails —
   `Contract.fail` does not exist, and the control cuts at 511.
2. Write AC-2's counter control. Run it. It fails — the message is built on
   passing checks today.
3. Write AC-4's enumeration. Run it. It fails — all four in-scope helpers raise
   through bare `assert` or a private wrapper today: 129 sites, per the table
   above.
4. *Then* write the raiser and convert.

Paste each failure into `## Scaffold inventory`. A SCAFFOLD phase that lands the
fix and the assertions in one motion, with no red recorded, has produced three
assertions nobody has seen fail — which is the exact defect this story exists to
remove, arriving through the door it opened.

### Baselines this story may read out rather than re-derive

Measured on this machine under Lune 0.10.5. Rows marked *(filing)* were taken on
the tree the story was filed from, before SEAT-002 and SEAT-003 landed; the rest
were re-measured at PLANNED on 2026-09-28 (`main` @ `bdc5d61`). All of these may
be quoted; none needs re-deriving.

| Measurement | Value |
|---|---|
| `lune run test` | **443 passed, 0 failed** (197 at filing) |
| `assert` message cap | **511** characters, message only |
| position prefix, from a 1 / 40 / 90-character directory name | 173 / 212 / 259 — cap unchanged at 511 |
| `RingContract` truncated checks *(filing)* | 7 (SEAT-001's AC-1..AC-5, AC-7, sub-stream pin), body exactly 511 |
| `LobbyGateContract` / `RoundEndingContract` max body *(filing)* | 404 / 291 |
| SEAT-001 AC-5 needle end offset *(filing)* | 479 of 511 — 32 characters of slack |
| `error(msg, 0 / 1 / 2)` on 900 characters | 900 / 1075 / 1075, no truncation at any level |
| `unit` gate floor in `project.conf` | 443 — a minimum, so adding tests needs no edit |
| in-scope raise sites | 129 across four helpers, plus 2 private wrappers (table under "Scope of conversion") |

### Oracle partition of the criteria (see `story-authoring`)

| AC | Kind | Instruction |
|---|---|---|
| AC-1 | **Settled** — 511 is measured, five ways, above | Read the number out. Do **not** re-derive or "calibrate" the cap. Do write the `assert` control; that is the part that is not settled until it runs. |
| AC-2 | **Mechanical** | Pin exactly: a counter, zero on a passing run, non-zero on a failing one. Both halves. |
| AC-3 | **Settled** | A documentation edit against a measured number. No metric to invent. |
| AC-4 | **Mechanical** | Pin exactly, and enumerate through `scripts/classify.sh`. A private regex for "a contract helper" is the four-drifting-copies failure `rules.md` names. |
| AC-5 | **Settled** | 443 / 0 is the baseline above. Read it out. |

### Test-only dependencies

None. Lune and the existing helpers are sufficient. No manifest changes in any
phase.

### Changed signatures

No **existing** export changes signature. The raiser is new; the conversions
change the body of existing contract-check functions, not their signatures. The
caller list is therefore empty — checked, not assumed.

## Deferred verifications

<!-- Owner: the phase that runs it. Result pasted in by that phase. -->

**AC-5's "after" half cannot run until the conversion exists.** The "before"
figure is recorded above (443 / 0). The falsifiable condition: after the
conversion, `lune run test` reports **443 plus this story's new tests, passed, 0
failed** — in particular, SEAT-001's AC-5 check in `RingContract` still matches
its needle at the new offset. If any existing needle stops matching, the conversion has changed
message content, which `## Out of scope` forbids.

**Owner: GATES.** Paste the run.

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

Planned by `bash scripts/plan.sh write HARNESS-011` from `.claude/harness/models.conf`.
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

<!-- One line per dispatch, as it happened: phase, agent, the model that
     actually ran, and — if a phase was planned for one model and ran on
     another — what that changed. A choice with no verdict is folklore. -->

**Which rows apply.** This story runs PLANNED → **SCAFFOLD** → GATES → REVIEW →
DONE (`## Contract`, "Phase path"), so the operative rows are PLANNED, SCAFFOLD,
GATES and REVIEW. The RED row is not reached, and its `fable` entry should not be
read as a verdict about this story either way. No departure from the policy is
claimed; `.claude/harness/models.conf` is not edited.

**Brief the SCAFFOLD dispatch with the oracle partition**, which is in
`## Contract` rather than here: AC-1, AC-3 and AC-5 are **settled** — the numbers
are measured and are to be read out, not re-derived or "calibrated" — and AC-2
and AC-4 are **mechanical** and want exact pinning, including AC-4's
report-by-name-and-line control.

## Out of scope

**No acceptance criterion and no assertion semantics of the existing contract
checks changes.** This story changes the **raising mechanism** and the
**construction** of failure messages. It does not change *what* is checked, *what*
counts as a violation, or *what* any needle asserts. A conversion that also
rewords a message is out of scope, and AC-5 is the guard against it.

**The other raising helpers are not converted.** Counted at PLANNED on
2026-09-28:

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

The five private `check` wrappers were not in the inventory when the story was
filed. They make the "one answer becomes six" argument literal: with Ring's and
Projection's, there are seven copies, and every one's comment quotes the wrong
cap (512). None was measured to truncate, and adding them would more than double
the conversion. Converting them is the follow-up, so file it rather than drop it:
**one story converting every remaining helper to the shared raiser, and correcting
or deleting the "512" in each wrapper's comment, after this one.**
`tests/helpers/Fakes.luau` (2 sites) is a stub, not a contract, and is not part
of that follow-up either.

**The `firstFew(..., 8)` violation cap is not re-tuned.** Whether 8 is the right
number of violations to show is a separate question with a separate answer, and
re-tuning it inside this change would make AC-5's before/after comparison
meaningless.

**No hunt for vacuous assertions.** `## Context` establishes there are none of
the relevant shape. A story that goes looking anyway will find absence-shaped
assertions on nil values and "fix" tests that are correct.

**No new gate.** `## Gate probes` is omitted for that reason. The artifact runs
under the existing required `unit` gate.

## Test plan

<!-- Filled during SCAFFOLD: which assertions, at which level, and which AC each
     one covers. -->

## Regressions

<!-- REQUIRED if this story ever returned to an earlier phase after GATES; omit
     otherwise. One block per return:
       * which test, what it asserted, and what was wrong with it
       * how the defect was found
       * what it asserts now
       * what earns it, since "watched it fail" cannot apply once the
         implementation exists - either a PROBE (mutate the specific behaviour
         the test pins via `bash scripts/mutate.sh`, paste the red, confirm the
         revert) or a BEFORE/AFTER measurement taken under the gate command.
         PASTE THE OUTPUT. check-boundaries.sh refuses a PR whose Regressions
         section describes a failure without showing one -->

## Gate results

<!-- Written by scripts/gates.sh itself on every full run, stamped with the
     commit and a hash of the code it ran against. Do not paste or edit it:
     check-boundaries.sh refuses a PR whose recorded run does not match the
     code being merged. -->

## Scaffold inventory

<!-- REQUIRED: this chore runs under SCAFFOLD. One line per file written, and
     for anything with behaviour, the assertion that covers it. No PRODUCTION
     source is expected to change - every code file here classifies as `test`,
     which is why the story is in SCAFFOLD at all - so confirm that with
     `bash scripts/classify.sh` and record the output.

     This section also carries the four red runs the ## Contract's phase-path
     block requires, pasted: AC-1 and its `assert` control, AC-2's counter,
     AC-4's enumeration, each observed to fail BEFORE the raiser existed. -->

## Notes

### PO decisions at PLANNED → SCAFFOLD (2026-09-28)

The story was filed before `SEAT-002` and `SEAT-003` merged. Re-read against
`main` @ `bdc5d61` before leaving PLANNED; the user settled each of these:

- **PO-1 — RingContract's private `check` is converted too.** `SEAT-003` added
  `check(cond, msg)` → `error(msg, 2)` at 15 sites alongside the 9 remaining
  `assert` sites. It does not truncate, but it builds every message eagerly,
  which AC-2 forbids. AC-4 is therefore worded to reject private raisers as
  well as bare `assert`. The user chose this over narrowing AC-4 to `assert` only.
- **PO-2 — `ProjectionContract` is brought into scope.** It was excluded only
  because `SEAT-002` was in flight on another branch; `SEAT-002` is DONE. It
  adds 9 sites and removes the follow-up that existed only for it. AC-4's set is
  now four helpers.
- **PO-3 — the baselines were refreshed in PLANNED.** 197 → 443 in AC-5's
  rationale, the deferred verification and the baselines table; the site counts
  and line numbers were re-measured. Filing-time measurements that were not
  re-taken are marked *(filing)*. AC-5's criterion itself, `0 failed`, is
  unchanged.

Found during the re-read and handled without widening scope: five **more**
helpers (`Net`, `Phase`, `Rate`, `Rejection`, `Telemetry`) carry their own
private `check`, and `TelemetryEmitContract` has 48 bare `assert`s. None was in
the filed inventory. They are listed under `## Out of scope` and go into the
follow-up.

**Epic done-when:** the story has no epic (`epic:` is empty), so there is no
done-when to check it against.

**Gate:** `unit` (`lune run test`) is required and runs every contract helper;
`lint` (required) also reads `tests`. No optional gate needs promoting.
`required_gates` stays empty.

### The phase path, and the option not taken

The alternative was **RED → GREEN with a docs-only GREEN**: RED writes the
assertions *and* the raiser *and* the conversions (all legal — RED permits
`test`), and GREEN's only write is `docs/wiki/stack.md` for AC-3. That keeps the
familiar ladder and the gate machinery intact.

Rejected because it is the same work wearing a better costume. RED would be doing
the implementation, which is precisely what RED is defined not to do, and GREEN
would be dispatched with a one-line documentation edit —
`story-authoring`/`sections.md` on a no-op GREEN: "dispatching an implementer
with nothing to do invites them to find some." SCAFFOLD is the phase that is
honest about unlocking the write, and its price — the `## Scaffold inventory`,
with the red runs pasted — is the right price to pay.

### Run the gates from SCAFFOLD, before moving to GATES

`format` (stylua) and `lint` (selene) both run over `tests` as well as `src`.
GATES freezes `test`, so a stylua reflow or a selene complaint **in a test file**
is a failure GATES cannot legally fix — `rules.md` names exactly this: "a
`format` or `lint` gate can fail on a test file the story itself added... GATES
is the phase whose stated job is fixing lint and build failures, and it is the
phase that cannot fix that one." Under SCAFFOLD every category is writable, so
running `bash scripts/gates.sh` while still in SCAFFOLD avoids a bounce that
would otherwise cost a phase and an entry in `## Regressions`.

Note also that `format` is `optional` in `project.conf` while `lint` is
`required`.

### The general "earn the assertion" rule still applies

`## Context` retires one specific obligation — there is no unreachable needle to
watch go red. It does not retire the general one. These helpers **already
exist**, so any assertion written or corrected against them after the raiser
lands passes on its first execution and every execution after, whether or not it
asserts anything. The ordering obligation in `## Contract` is the cheap way to
satisfy it: write each assertion while it is still red, and record the red.

Where that ordering is not available — a correction made after the fact — earn it
by mutating the specific behaviour it pins with

    bash scripts/mutate.sh FILE 'EXPR' -- COMMAND

and paste the output. Never `sed -i`: that is law 5, and `HARNESS-010` is the
story about the guard's reading of exactly that command.

### Operational hazard: a killed mutate.sh leaves the file mutated

Killing a `scripts/mutate.sh` run **pre-empts its restore trap** and leaves a
`.bak` under `.claude/state/mutations/` with the file still mutated. This
happened once during the investigation behind this story; the file was restored
from the backup and verified with `cmp` plus an empty `git diff`.

Using `timeout` (SIGTERM) instead of a hard kill **does** let the trap run
correctly. Prefer it. A leftover `.bak` under `.claude/state/mutations/` always
means a restore did not complete — `mutate.sh` cleans up everything else.

The suite is slow enough for this to matter: the eager-evaluation instrumentation
described in `## Contract` timed out twice, at 420s and 600s.

### Provenance

Every number in this file was measured on this machine under Lune 0.10.5 rather
than estimated: the 511 cap by a marker probe at known indices; the
prefix-independence by re-running that probe from directories of three different
name lengths; the per-helper body lengths by instrumenting all 55 `names()` call
sites through `scripts/mutate.sh`; the `error` levels on a 900-character message
with a real nested caller; the 197/0 baseline by `lune run test`. The
`ROUND-004` re-reading is arithmetic on that story's own raw columns, not a new
measurement.

This story was filed the same way `HARNESS-009` and `HARNESS-010` were — a
finding that would otherwise live only in a session transcript, written into the
backlog with its evidence.
