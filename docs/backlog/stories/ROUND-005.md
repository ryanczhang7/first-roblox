---
id: ROUND-005
title: A round ends on outcome, clock or quorum with a deterministic reason
slug: a-round-ends-on-outcome-clock-or-quorum
epic: EPIC-01
type: feature
status: done
phase: DONE
branch: story/ROUND-005-a-round-ends-on-outcome-clock-or-quorum
depends_on: [ROUND-003, ROUND-004]
required_gates: []
---

## Context

A round can end three ways, and the third is not a loss.

1. **An outcome event.** Something in the round resolved it. M3 decides what; the
   machine routes it (`ROUND-003` AC-3).
2. **The clock.** `round_seconds` elapses — `lost`, reason `clock`.
3. **Quorum.** The seated count falls below `min_players_to_continue` (3). This is
   `no_contest`: `mechanics.md` §8 — *"no loss is recorded and season progress is
   unaffected: the group did not fail, the lobby did."*

The part that needs specifying rather than assuming is what happens when two land
in the same step. `mechanics.md` §8 is explicit that deterministic ordering
matters **because the trace reports the reason**, and a reason that depends on
evaluation order is a bug report nobody can reproduce.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a round in `Round`, when the clock is advanced past
  `round_seconds` with no other event, then the phase becomes `Resolution` with
  outcome `{ result = "lost", reason = "clock" }`, and not before: at
  `round_seconds − 0.1` elapsed the phase is still `Round`.
- **AC-2** — Given a round in `Round` with the minimum seated count, when enough
  players leave that the count falls below `min_players_to_continue`, then the
  phase becomes `Resolution` on that step with outcome
  `{ result = "no_contest", reason = "below_quorum" }`.
- **AC-3** — Given a round that ended `no_contest`, when the resulting state is
  inspected, then it is distinguishable from a loss: `result` is `"no_contest"`,
  never `"lost"`.
  *Control:* an implementation that records a quorum failure as `lost` **must**
  fail this. A test asserting only "the round ended" cannot tell them apart, and
  the difference is whether a group's season progress is harmed by somebody else's
  connection.
- **AC-4** — Given a step in which the clock has expired **and** a `RoundResolved`
  event arrives, then the outcome recorded is the one the event carried, not
  `clock`.
  *Semantics:* the event describes something that happened inside the round; the
  clock describes the round running out around it. The event wins.
- **AC-5** — Given a step in which the clock has expired **and** the seated count
  has fallen below quorum, then the recorded reason is the same on every run, and
  it is `below_quorum`.
  *Semantics:* a round nobody can play did not run out of time. The precedence is
  `RoundResolved` > `below_quorum` > `clock`, stated once, here and in
  `architecture.md` §3.
- **AC-6** — Given any of the three endings, when the effects of the ending step
  are inspected, then exactly one `ComputeTrace` effect is emitted, carrying the
  round id — and the round does **not** continue to accumulate effects after
  ending.
  *Control:* an implementation that keeps ticking a finished round emits a second
  `ComputeTrace` and **must** fail this.
- **AC-7** — Given a `Round` phase, when a `PlayerLeft` reduces the count to
  exactly `min_players_to_continue`, then the round **continues**. Three is a ring
  (`roles.md` §6); the threshold is "below", not "at or below".

## Contract

Extends `src/server/round/PhaseMachine.luau`. No signature change, so no caller
list to grep.

### Outcome vocabulary owned by this story

    { result = "lost",       reason = "clock" }
    { result = "no_contest", reason = "below_quorum" }

Every other `reason` string is M3's and arrives inside a `RoundResolved` event.
This module must not enumerate them.

### Precedence, stated once

Within a single `step`, terminal conditions are evaluated in this fixed order and
the first that holds wins:

    1. RoundResolved  (an event carrying an outcome)
    2. below_quorum   (seated count < minPlayersToContinue)
    3. clock          (now - phaseEnteredAt >= roundSeconds)

This ordering is the contract. It is not an implementation detail and a later
story may not reorder it without an `## Amendments` entry, because
`mechanics.md` §7 reports the reason to players and `TEL-002` emits it as
telemetry.

### The degraded round

`roles.md` §6 notes that a round continuing at `n = 3` after a dropout is
*playable but structurally thinner* — "a degraded round, not a different game" —
and that the trace should say so rather than record it as a clean result. This
story does **not** implement that flag. It is recorded here so the omission is a
decision: the trace is M3, and a flag with no consumer is a field that rots.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2, AC-7 | **Settled** | `round_seconds` and `min_players_to_continue` come from `ROUND-002` via `RoundConfig`. Read them out. AC-7's boundary — "below", not "at or below" — is `tuning.md` §1's derivation, not a choice. |
| AC-3, AC-6 | **Mechanical, with controls** | The controls are in the criteria. |
| AC-4, AC-5 | **Mechanical** | The precedence list is written above. Pin it exactly; do not invent a tie-break. |

## Deferred verifications

<!-- Nothing is deferred. The template requires this section only when a
     verification provably cannot run in the phase that wants it, and says
     to omit it otherwise - so the word "None" in prose here reads to
     check-boundaries.sh as a deferred entry with no owner and no result,
     which is the same defect as a WAIVED with no reason.
     Planned text was: None. Simultaneity is producible in RED by constructing the state directly — that is the payoff of a pure `step` that takes `now` as an argument.
-->

## Model guidance

**Resolved model of every dispatch, by name:**

| Phase | Agent | Declared in the agent definition | Resolved in this session |
|---|---|---|---|
| RED | `test-developer` | `model: opus` | **Opus 5**, no override in play |
| GREEN + GATES | `feature-developer` | `model: opus` | **Opus 5** (`claude-opus-5`), no override in play |

AC-4 and AC-5 are the criteria to brief carefully. Both describe a *single step*
in which two conditions hold, and the natural test — advance the clock, then send
the event — tests two steps and asserts nothing about precedence. Say so in the
dispatch: **construct the simultaneous state directly.**

## Out of scope

- What resolves a round successfully. M3 supplies `won` and its reasons.
- The degraded-round flag at `n = 3`. Recorded above as a deliberate omission.
- The `disconnect_grace_seconds` window. A player who leaves is gone for quorum
  purposes immediately; the grace window governs whether their **seat** is
  reassigned, which is `SEAT-003`.
- Season progress accounting. The `no_contest` result is recorded; what consumes it
  is M5.
- Telemetry for the ending. `TEL-002`.

## Game design

Implements `mechanics.md` §8's terminal rows and `tuning.md` §1's
`min_players_to_continue` (3, derived: a 3-cycle ring is still a ring).

The decision AC-3 protects is a real one from the design: **a lobby that empties
must not cost the remaining players anything.** Under amendment 9 progression is
shared and seasonal, so recording a disconnection-driven collapse as a group loss
would punish three people for a fourth person's connection — in a game whose
retention thesis is that the same four people keep playing together.

`mechanics.md` §8 also specifies "the round becomes unwinnable → end immediately
with a stated reason, never run out a clock on a group that cannot win." That
requires knowing the remaining operations, which is M3. When it lands it becomes a
fourth `RoundResolved` reason, arriving through the event, and this module does not
change.

## Notes

**Mutation the orchestrator should run at acceptance:**

1. Change the quorum comparison from `<` to `<=`. Predicted: AC-7 goes red alone —
   a single assertion, and exactly the off-by-one that would silently end every
   three-player round.
2. Reorder the precedence list so `clock` precedes `below_quorum`. Predicted: AC-5
   goes red.
3. Record the quorum ending as `result = "lost"`. Predicted: AC-3 goes red. If it
   stays green, AC-3 was written as "the round ended".

Run mutation 1 first.

**Raise the `unit` floor** to the new real count.

---

## PO decisions at PLANNED -> RED

**1. The required gate is `unit`, confirmed rather than assumed.**
`.claude/harness/project.conf` carries `covers | unit | src/server/**` (line 413),
so the required `unit` gate already declares it reads
`src/server/round/PhaseMachine.luau`, the only production file this story
touches. `required_gates: []` therefore stays empty — the story's Context names
`unit` and `unit` is already required and already covering. Verified:

    $ grep -nE '^covers' .claude/harness/project.conf
    396:covers | lint      | src/**
    397:covers | typecheck | src/**
    398:covers | build     | src/**
    405:covers | unit      | src/shared/**
    413:covers | unit      | src/server/**

**2. No signature changes, so the caller list is empty — and that was checked,
not assumed.** `grep -rn PhaseMachine src tests lune` returns no production
caller at all: `RoundService` does not exist yet, and every reference outside
`src/server/round/PhaseMachine.luau` is a test file or a test helper. `initial`
and `step` keep their ROUND-003 signatures exactly; this story adds branches
inside `step`, no parameters and no exports.

**3. The epic's done-when is closed by this story, and nothing is left over.**
`EPIC-01`'s done-when asks for *"a round that ends by the clock, one that ends by
an outcome event, one that ends as a no-contest when the lobby empties below the
continue threshold, and a lobby that refuses to start below `players_min`."* The
outcome-event ending is `ROUND-003` AC-3 (frozen, green); the lobby gate is
`ROUND-004` (DONE). The clock ending and the quorum ending are AC-1 and AC-2
here. There is no gap for this story to absorb beyond its own criteria.

### 4. The collision with a frozen ROUND-004 test, and the ruling

`tests/server/lobby_gate_test.luau` carries a **passing, frozen** test named
`Contract pin 2: a PlayerLeft outside the Lobby is ignored - a mid-round
departure is ROUND-005`. It drives the machine to `Assignment`, `Round`,
`Resolution` and `Post` with exactly `playersMin` (4) seated and asserts, in all
four, that a `PlayerLeft` naming a seated player returns the state unchanged with
no effects.

**That assertion and this story's AC-2 and AC-7 cannot both hold.** AC-2 requires
the seated count to fall when players leave mid-round; AC-7 says in as many words
that *"a `PlayerLeft` reduces the count to exactly `min_players_to_continue`"*. If
`PlayerLeft` is ignored in `Round`, the count never falls, AC-2 is unsatisfiable
and AC-7 passes vacuously. There is no implementation that satisfies both.

**Ruling: the ROUND-004 pin is narrowed in `Round` only, and replaced there by a
strictly stronger assertion.** Three things make this a supersession rather than
a weakening:

- The ROUND-004 test **names this story in its own test name** and its comment
  says *"What a mid-round departure means is ROUND-005's story — it is the one
  that needs the count against `min_players_to_continue`."* ROUND-004 pinned
  not-yet-implemented behaviour and handed the case forward by name.
- **No ROUND-004 acceptance criterion changes.** Its AC-3 and AC-6 are about the
  Lobby. Contract pin 2's non-goal — "unseating here would silently change the
  seated list AFTER `AssignSeats` has already carried it" — is about
  `Assignment`, `Resolution` and `Post`, and stays pinned in all three. So there
  is no `## Amendments` entry on ROUND-004: criteria are frozen and none moved.
- The `Round` case is not deleted. It is replaced by AC-2, AC-5 and AC-7, which
  assert what happens on that step rather than that nothing does.

**Instruction to RED:** edit that one test to iterate `Assignment`, `Resolution`
and `Post`, leaving its message and structure otherwise intact, and say in the
comment that `Round` moved to this story's file. The narrowed test still passes
on arrival, so it is re-earned the same way ROUND-004 earned it: mutate the
machine to unseat unconditionally in every phase through
`bash scripts/mutate.sh`, watch the narrowed test go red for
`Assignment`/`Resolution`/`Post`, revert, paste the output into
`## Regressions`.

### 5. Contract pins

**Pin 1 — `PlayerLeft` acts in `Lobby` and in `Round`, and nowhere else.**
`Assignment`, `Resolution` and `Post` keep ROUND-004's behaviour exactly: the
event is ignored in full. In `Round` it unseats the named player (a leave naming
somebody not seated stays an ignored event) and then, on that same step,
evaluates quorum.

**Pin 2 — quorum is consulted on `Tick` and on `PlayerLeft`, never at the top of
`step`, and never for an event the phase does not recognise.** ROUND-003 AC-7 is
frozen and says an unrecognised event returns the state unchanged with an empty
effect list, with no exception for a terminal condition that already holds. A
`RematchAccepted` arriving at a `Round` sitting below quorum is still ignored;
the next `Tick` ends the round. This is the same ruling ROUND-003 made for
durations, extended to the count for the same reason.

**Pin 3 — the ending step emits NO effects; the single `ComputeTrace` is still
emitted by `Resolution -> Post`.** AC-6 says *"exactly one `ComputeTrace`"*, and
ROUND-003 AC-4 and AC-8 are frozen and green: `Resolution -> Post` emits exactly
one `ComputeTrace` carrying the round id, and a full lifecycle emits exactly
`AssignSeats, ComputeTrace, PromptRematch` in that order. `architecture.md` §3
agrees (*"`Resolution` | immediately, on entry | `Post` | Emits the
trace-computation effect"*). So AC-6 is read over **the ending sequence** — the
ending step, plus every step from it through `Post` and back to `Lobby` — and its
named control is exactly the rejected reading: a machine that emits
`ComputeTrace` from the `Round` branch on the way out emits a **second** one on
the `Resolution -> Post` tick and fails AC-6. RED asserts the count over the
sequence and asserts the ending step's own effect list is empty.

**Pin 4 — the comparison is `#players < minPlayersToContinue`, strict.** AC-7's
boundary is `tuning.md` §1's derivation (*"a 3-cycle ring is still a ring"*), not
a choice. `<=` ends every three-player round silently and is mutation 1 in
`## Notes`.

**Pin 5 — a resolved round is not re-resolved.** Once the machine is in
`Resolution` or `Post`, neither quorum nor the clock is consulted again: those
phases have their ROUND-003 behaviour and `outcome` is written once, by the step
that ended the round.

**Pin 6 — the clock is consulted on `Tick` and on `Tick` only** (added at
RED -> GREEN; see `## PO ruling at RED -> GREEN`, ruling 2). A `PlayerLeft` step
evaluates quorum and never the clock, or AC-7's *"the round continues"* would
become conditional on how much time had passed and a departure would be reported
to players as a timeout.

### 6. AC-4 and AC-5 are tested on ONE step, constructed directly

The story's `## Model guidance` calls this out and it is repeated here as an
instruction RED is accountable for. *Advance the clock, then send the event* is
two steps and asserts nothing about precedence. The simultaneous state is
reachable because `step` is pure and takes `now` as an argument: drive the
machine to `Round`, then reach the state that has the count already below quorum
(AC-5) or leave the count intact (AC-4), and call `step` **once** with a `now`
past `phaseEnteredAt + roundSeconds`. A test that needs two steps to produce the
condition is testing the wrong thing.

### 7. RED runs the whole suite, not just its own tests

`ROUND-003`'s and `ROUND-004`'s tests are frozen and stay green apart from the
one narrowing in decision 4. The `unit` floor is at **154**; a RED run shows the
new tests failing underneath an otherwise intact suite, and any *other*
pre-existing test going red is a collision to report rather than a number to
write down. The floor rises to the new real count in GATES, by the Lead PO, once
it is measured.

### 8. `architecture.md` §3 carries the precedence list

The story's Contract says the precedence is stated *"once, here and in
`architecture.md` §3"*, and §3 carried only the general rule ("the recorded reason
is the one earlier in a fixed precedence list") without the list. The list is now
written there, in this phase, by the Lead PO — before RED, so RED reads a
document that agrees with the story rather than one it has to reconcile.

### 9. Toolchain

`lune`, `rojo`, `selene`, `stylua` and `luau-lsp` resolve on this session's
`PATH` under `~/.rokit/bin` (`which` checked; `scripts/doctor.sh` reports
everything installed). Dispatches still carry
`export PATH="$HOME/.rokit/bin:$PATH"` so that a subagent inheriting a stale
shell does not read `command not found` as a broken test command.

---

## PO ruling at RED -> GREEN

**RED is accepted**, and every claim below was re-run by the orchestrator rather
than taken on report.

**The suite.** `lune run test` -> `165 passed, 10 failed`, against `154 passed,
0 failed` on `main`. 21 tests added: 13 real, 8 controls. All 10 failures are in
`tests/server/round_ending_test.luau`, each an assertion failure naming its
criterion — not a load failure, so the file's other assertions really did run.
**No pre-existing test went red.** The failing ten:

    AC-1 clock boundary                      AC-2 departure crossing
    AC-2 quorum on a Tick                    AC-3 no_contest vs lost
    AC-5 one-step precedence                 AC-6 exactly one ComputeTrace
    AC-7 continues at the threshold          AC-7 ends one below it
    Contract pin 2 unrecognised below quorum Contract pin 5 not re-resolved

**Admissibility.** `bash scripts/gates.sh --fast` re-run by the orchestrator:

    PASS         format (0s, observed 34)
    PASS         lint (1s, observed 34, floor 1)
    PASS         typecheck (2s, observed 7)
    FAIL         unit (5s, exit 1)
    UNCONFIGURED coverage
    PASS         build (0s, observed 17308)

The test gate is red with this story's assertions and every gate that judges
whether those tests are *admissible* is green. 34 files observed, up from 30 at
ROUND-004 — the four new files are `stylua`-clean and `selene`-clean.

**The probes restored.** `git diff -- src` is 0 bytes, `git status --short -- src`
is empty, and `.claude/state/mutations/` holds only its `log` — no `.bak`, so
every `mutate.sh` run restored and `cmp`-verified.

**Probe 3 reproduced independently.** The orchestrator re-ran it rather than
reading RED's paste:

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/resolution.outcome = event.outcome/resolution.outcome = { result = "lost", reason = "clock" }/' \
        -- lune run test
    ...
      FAIL  tests/server/round_ending_test.luau :: AC-4: a RoundResolved arriving on the step the clock expired records the outcome the event carried
      FAIL  tests/server/round_ending_test.luau :: AC-4: a RoundResolved outranks quorum and the clock when all three hold on one step
    161 passed, 14 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T152506Z.1804.bak) ===

`161 passed, 14 failed` to the test, the two AC-4 tests red for the right reason,
and ROUND-003's frozen AC-3 pair red alongside them — which is correct, because
the mutation breaks the behaviour ROUND-003 owns as well.

**The narrowing is exactly what was ruled.** `git diff -- tests/server/lobby_gate_test.luau`
changes one loop from `for phase, state in reached` to an explicit
`{ "Assignment", "Resolution", "Post" }`, plus the comment recording why. The
assert message, the fixture and every other test in the file are byte-identical.
No ROUND-003 or ROUND-004 acceptance criterion moved, so there is no
`## Amendments` entry on either.

### Ruling 1 — the constructed below-quorum `Round` state is accepted

RED asked for this on the record, and it is right to have asked. A `Round` whose
count is already below `minPlayersToContinue` **cannot be reached by driving the
machine**, because the `PlayerLeft` that crosses the threshold ends the round on
that same step (AC-2). `RoundEndingContract.belowQuorumRound` therefore takes the
machine's own `Round` state — phase, `phaseEnteredAt`, `roundId`, `seed` and
`config` all produced by driving it — and shortens `players`, touching nothing
else.

That is exactly what the story planned for. `## Model guidance` says *"construct
the simultaneous state directly"* and `## Deferred verifications` says
simultaneity *"is producible in RED by constructing the state directly — that is
the payoff of a pure `step` that takes `now` as an argument."* Nothing is
deferred and nothing is waived.

The consequence worth naming: AC-5 and the third precedence pair specify **the
algorithm**, not a scenario reachable in M1 today. They are not decoration. The
moment `SEAT-003` can vacate a seat mid-round, or a future story admits a
count-changing event other than `PlayerLeft`, that state becomes reachable and
the precedence has to already be right — which is the whole reason
`mechanics.md` §8 asks for a specified order rather than an emergent one.

### Ruling 2 — the clock is consulted on `Tick` and on `Tick` only

RED left this open because no criterion decides it, and flagged that GREEN could
go either way. It may not. **On a `PlayerLeft` step the machine evaluates quorum
and never the clock.**

AC-7 is the reason: *"when a `PlayerLeft` reduces the count to exactly
`min_players_to_continue`, then the round **continues**"* — full stop, with no
clause about how much time has passed. A machine that also consulted the clock on
that path would end the round `lost(clock)` on a departure that AC-7 says the
round survives, whenever the departure happened to land after `roundSeconds`. It
would make AC-7 conditional on the clock, and it would report a departure as a
timeout in the trace.

This is the same shape as ROUND-003's ruling that a duration is consulted only
for an event the phase recognises, and it narrows `architecture.md` §3's *"in
practice `Tick`"* to a decision now that `Round` recognises a second event. No
criterion changes; this is a Contract pin, added as **pin 6** to decision 5 of
`## PO decisions at PLANNED -> RED`.

### Ruling 3 — the `## Notes` mutation predictions were low, and `## Notes` is not frozen

RED measured mutation 1 as **2 red** (`## Notes` predicted 1) and mutation 3 as
**3 red** (predicted 1). `## Notes` is orchestrator guidance, not an acceptance
criterion, so nothing is amended: a suite that catches a mutant in more places
than predicted is stronger than the prediction, not in conflict with it. The
predictions are now RED's measured table in `## Handoff`, and the orchestrator
runs one of them against the shipped module at GREEN -> GATES. They cannot be run
before then: all three mutate behaviour that does not exist yet.

### What GREEN is accountable for

1. Make the ten red tests green **without touching a test file.** Tests are
   frozen in GREEN. If one is wrong, stop and say so — that is a return to RED
   and a `## Regressions` entry, never an edit.
2. **Confirm the negative-control values RED recorded.** RED's controls ran
   against stubs; `## Handoff`'s two tables give the exact message fragment each
   one measured. Run the three `## Notes` mutations against the shipped module
   through `bash scripts/mutate.sh` and check the tests that go red, and the
   messages they carry, against those tables. Record the measured numbers in
   `## GREEN: control values confirmed`.
3. **End with `bash scripts/gates.sh --fast`**, and report it. Not for the record
   — a partial run is not evidence — but because the coverage gate runs the same
   tests instrumented and a suite can pass GREEN and still fail a required gate
   on CI hardware.
4. `PlayerLeft` gains `Round`, not a general phase. `Assignment`, `Resolution`
   and `Post` keep ROUND-004's behaviour, and `tests/server/lobby_gate_test.luau`
   still pins all three.

**Resolved model of the RED dispatch:** `test-developer`, whose definition
declares `model: opus`; this session resolved it to **Opus 5** and no override
was in play.
---


## PO acceptance at GREEN -> GATES

**GREEN is accepted**, and as at RED every number below was re-run by the
orchestrator rather than read off GREEN's report.

**The suite.** `lune run test` -> **`175 passed, 0 failed`**: 154 pre-existing
plus this story's 21. No pre-existing test went red, and the ten that were red at
RED are the ten that turned.

**GREEN wrote no test.** `git diff --stat -- tests` is one file — RED's own
narrowing of `tests/server/lobby_gate_test.luau`, 18 insertions / 7 deletions,
byte-identical to what was reviewed at RED -> GREEN. The four new test files are
untracked and unchanged. `.claude/state/phase-guard-declined.log` records nothing
for ROUND-005, so nothing was attempted and turned away either.

**One production file changed.** `src/server/round/PhaseMachine.luau`. No
signature change, no new export, no new module. `gates.sh` agrees: *"changes: 1
changed source path(s), all exercised by a required gate."*

### The mutation table is confirmed, not quoted

RED's predictions are a claim until somebody runs one. Two were re-run by the
orchestrator against the shipped module, through `scripts/mutate.sh`, which
restored each file and verified the restore byte-for-byte:

**Mutation 1** — the quorum comparison, `<` to `<=`. `## Notes` predicted 1 red;
RED predicted 2. Measured:

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/#state.players < state.config.minPlayersToContinue/#state.players <= state.config.minPlayersToContinue/' \
        -- lune run test

      FAIL  tests/server/round_ending_test.luau :: AC-2: a departure that takes the count below min_players_to_continue ends the round no_contest on that step
      FAIL  tests/server/round_ending_test.luau :: AC-7: a departure to exactly min_players_to_continue leaves the round running
    173 passed, 2 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T154138Z.26948.bak) ===

**Mutation 2** — `clock` ahead of `below_quorum` in the precedence list. Predicted
1 red, the single-assertion case, which is why it was the second one chosen.
Measured:

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/if state.phase == "Round" and isBelowQuorum(state) then/if state.phase == "Round" and isBelowQuorum(state) and elapsedIn(state, now) < state.config.roundSeconds then/' \
        -- lune run test

      FAIL  tests/server/round_ending_test.luau :: AC-5: when the clock and quorum both fall on one step the reason is below_quorum, on every run
    174 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T154151Z.28389.bak) ===

`173/2` and `174/1` to the test, the predicted tests and no others. GREEN's
measurements of all five mutants are in `## GREEN: control values confirmed`.

**Mutation 3 came in at 7 red against a prediction of 3, and that is accepted as
recorded.** All three predicted tests fail with their predicted messages; the
extra four compare the *whole* outcome with `Deep.equal` against
`quorumOutcome()`, so a wrong `result` fails them too. RED predicted from the
subset of checks its `losing` stub is fed. A suite that catches a mutant in more
places than predicted is stronger than the prediction, not in conflict with it —
ruling 3 at RED -> GREEN already covers this and `## Notes` is guidance, not
criteria. Nothing is amended.

### The implementation, reviewed

Read rather than assumed, and it honours every pin:

- **Precedence is structural where it can be and ordered where it cannot.**
  `RoundResolved` arrives in its own branch and never reaches the clock, so
  precedence rule 1 is not an `if` that can be reordered. Rules 2 and 3 are two
  `if`s inside `onTick`, quorum first, with the order named in a comment as the
  contract rather than as a preference. (Pins in `## Contract`, list in
  `architecture.md` §3.)
- **Pin 3 honoured:** `resolvedAs` returns `{}` — the ending step emits nothing —
  and the single `ComputeTrace` is still `Resolution -> Post`'s. GREEN's
  `doubleTracing` probe measured `173 passed, 2 failed` with AC-6 reporting
  `emitted 2 ComputeTrace effect(s)` and ROUND-003's frozen AC-8 alongside it,
  which is the correct pair.
- **Pin 6 honoured:** the `PlayerLeft` branch evaluates `isBelowQuorum` and never
  `elapsedIn`. Confirmed by reading the branch, and by mutation 2 — which had to
  *add* a clock term to reorder the precedence, because there was none on that
  path to move.
- **`clockOutcome()` and `quorumOutcome()` return fresh tables.** A shared
  constant would alias every round's outcome, which is the defect `copyOf`
  already exists to prevent one field lower down. Good call, unprompted.
- **`Outcome.reason` stays opaque.** Nothing enumerates an M3 reason, and the
  outcome table is exactly `{ result, reason }` — `Deep.equal` reports an extra
  key as a difference, so the deferred degraded-round flag cannot be sneaked in.

GREEN's note about a hung `lune` on a probe expression that left an unreachable
statement is a real toolchain fact and is kept in the story. `mutate.sh` restored
and `cmp`-verified even on the killed child (`exited 137 ... restored
(verified)`), which is the property it exists for.

### The `unit` floor is raised, in the story that earned it, and probed first

`floor | unit | 154` → **175**, measured from this story's own runs (`175 passed,
0 failed`, `observed 175`). Decision 7 at PLANNED -> RED assigned the raise to
GATES once the number was real. With `coverage` unconfigured on this stack the
floor is the only thing that notices a suite quietly shrinking, so it moves in
the story that added the tests.

**It is the one gate this story changes, so it was broken and watched to fail
before it was set.** The floor was first written as 176 — one above the real
count — and the gate run:

    $ bash scripts/gates.sh --gate unit
    --- gate summary ---
    FAIL         unit (6s, did 175 units of work, below the floor of 176 in project.conf) -> .claude/state/gate-logs/unit.log
    1 required gate(s) failed.

Then set to 175 and `bash scripts/gates.sh --audit` re-run: *"Manifest audit
passed."* This is a `## Gate probes` entry in substance — a floor that has never
been observed to fail is a number, not a gate — recorded here because the probe
is the Lead PO's and belongs beside the decision that made it.

### The full recorded run

`bash scripts/gates.sh` — the whole set, not `--fast`, written into
`## Gate results` by the script and by nothing else. All five configured gates
PASS; `coverage`, `integration` and `mutation` are UNCONFIGURED on this stack,
as they have been since BOOT-001. No gate reported `BLOCKED`, so there is nothing
pending CI and no PO decision to take on one.

**Resolved model of the GREEN dispatch:** `feature-developer`, whose definition
declares `model: opus`; dispatched with no model override, resolved to
**Opus 5** (`claude-opus-5`).
---


## Test plan

Two files apply the SAME checks: the real suite to
`src/server/round/PhaseMachine.luau`, the controls suite to deliberately wrong
machines. The checks themselves live in one helper so that neither copy can
drift from the other.

| File | What it is |
|---|---|
| `tests/helpers/RoundEndingContract.luau` | AC-1..AC-7 and Contract pins 1, 2, 5 written once, as checks over a `machine` |
| `tests/helpers/RoundEndingStubs.luau` | the baseline ending machine and five controls, each one defect away from it |
| `tests/server/round_ending_test.luau` | the checks applied to the real machine - 13 tests, 10 red |
| `tests/server/round_ending_controls_test.luau` | the checks applied to the stubs - 8 tests, all green, every control OBSERVED to fire |
| `tests/server/lobby_gate_test.luau` | narrowed, per PO decision 4 (one test, `Round` removed from its phase list) |

### Criterion by criterion

| AC | Test (in `tests/server/round_ending_test.luau`) | Check | Status in RED |
|---|---|---|---|
| AC-1 | `the clock ends the round at exactly roundSeconds elapsed, as lost(clock), and not before` | `roundEndsOnTheClock` | RED |
| AC-2 | `a departure that takes the count below min_players_to_continue ends the round no_contest on that step` | `roundEndsNoContestWhenTheCountFallsBelowTheThreshold` | RED |
| AC-2 | `a Tick on a round already below min_players_to_continue ends it no_contest` | `quorumIsConsultedOnATick` | RED |
| AC-3 | `a round that ended below quorum records no_contest and never lost` | `quorumEndingIsDistinguishableFromALoss` | RED |
| AC-4 | `a RoundResolved arriving on the step the clock expired records the outcome the event carried` | `resolvingEventOutranksTheClock` | GREEN on arrival - probe 3 |
| AC-4 | `a RoundResolved outranks quorum and the clock when all three hold on one step` | `resolvingEventOutranksQuorumAndTheClock` | GREEN on arrival - probe 3 |
| AC-5 | `when the clock and quorum both fall on one step the reason is below_quorum, on every run` | `quorumOutranksTheClockInOneStep` | RED |
| AC-6 | `each of the three endings emits exactly one ComputeTrace, carrying the round id, across the ending sequence` | `endingSequenceEmitsExactlyOneComputeTrace` | RED |
| AC-7 | `a departure to exactly min_players_to_continue leaves the round running` | `roundContinuesAtExactlyTheThreshold` | RED |
| AC-7 | `a round at exactly min_players_to_continue still ends when one more player leaves` | written inline | RED |
| pin 1 | `a PlayerLeft in Round naming a player who is not seated is ignored` | `aLeaveNamingSomebodyNotSeatedIsIgnoredInRound` | GREEN on arrival - probe 2 |
| pin 2 | `an unrecognised event at a Round below quorum is ignored, and the next Tick ends the round` | `unrecognisedEventsAreIgnoredBelowQuorum` | RED |
| pin 5 | `a round that already resolved is not re-resolved by a clock that expired afterwards` | `aResolvedRoundIsNotReResolved` | RED |

### Level, and why

Unit, everywhere. `step` is a pure function of `(state, event, now)` and every
criterion here is a statement about one call of it or a short sequence of calls.
There is no contract with another module to integrate against - `RoundService`
does not exist - and nothing a user walks through yet.

### How AC-4 and AC-5 are constructed (PO decision 6)

Never by advancing the clock and then sending the event. `step` takes `now` as
an argument, so the simultaneous state is one call:

- **AC-4** - a `Round` of `playersMin` (quorum intact), `step(round,
  RoundResolved{outcome}, phaseEnteredAt + roundSeconds + 5)`. The outcome
  carried is `{ result = "won", reason = "reason-k8qz-carried-by-the-event-not-invented-here" }`:
  a `result` neither the clock nor quorum can produce and a `reason` no
  implementation would invent.
- **AC-5** - a `Round` whose seated list is ALREADY below the threshold, and one
  `Tick` at a `now` past the clock. Determinism is asserted by
  `Contract.stepIsDeterministic` plus a third identical call comparing the
  recorded reason, because "the same on every run" is a claim about repetition.
- **the third pair** - the same below-quorum `Round`, an expired clock AND a
  `RoundResolved`: all three terminal conditions on one step, and the event wins.

`RoundEndingContract.belowQuorumRound` builds that state by driving the machine
to `Round` and then shortening the seated list. It cannot be driven there and
that is not a gap: the `PlayerLeft` that crosses the threshold ENDS the round on
that step (AC-2), so no event leaves the machine sitting in `Round` below quorum.
Everything else about the state - phase, `phaseEnteredAt`, `roundId`, `seed`,
`config` - is the machine's own.

### Edges covered

- **Boundary, both sides**: `roundSeconds - 0.1` (still `Round`), exactly
  `roundSeconds` (ends), `roundSeconds * 3` (ends, same outcome - an irregular
  driver cannot stretch a round).
- **Boundary, both sides**: a count of exactly `minPlayersToContinue`
  (continues, and continues through a further `Tick`), one below (ends).
- **The measurement origin**: the fixture enters `Round` at `lobbySeconds * 2`,
  not at 0, so a machine measuring `roundSeconds` from zero fails AC-1's "not
  before" assertion rather than passing by accident.
- **Totality**: `RematchAccepted`, an off-union kind, and a `PlayerLeft` naming
  nobody seated, all at a `Round` sitting below quorum - ignored in full, with
  the next `Tick` ending the round so that "ignore everything" cannot pass.
- **Non-goals pinned**: a resolved round is not re-resolved (pin 5); the ending
  step emits nothing (pin 3, asserted once in AC-6 for all three endings).

## Regressions

Three tests in this story are GREEN ON ARRIVAL, plus the one frozen ROUND-004
test that PO decision 4 narrows. `src/server/round/PhaseMachine.luau` already
exists, so none of the four was observed failing by the RED run - and a test that
has never been observed to fail is not a test. Each is earned below by a
`scripts/mutate.sh` probe of the SPECIFIC production behaviour it claims to pin:
one mutation, one run, one revert, output pasted.

`git diff -- src` is empty and `.claude/state/mutations/` holds no `.bak` after
all three, which is `mutate.sh`'s own `cmp` check reported per run.

### Probe 1 - the narrowed ROUND-004 test (`tests/server/lobby_gate_test.luau`)

PO decision 4 narrows `Contract pin 2: a PlayerLeft outside the Lobby is
ignored - a mid-round departure is ROUND-005` to iterate `Assignment`,
`Resolution` and `Post`, because AC-2 and AC-7 of this story require `Round` to
act on a departure. It still passes on arrival, so it is re-earned exactly as
ROUND-004 earned it: an unconditional unseating `PlayerLeft` branch.

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/then seatOf(state, event.playerId) else nil/then seatOf(state, event.playerId) else seatOf(state, event.playerId)/' \
        -- lune run test

    === mutate: src/server/round/PhaseMachine.luau (1 line(s) changed by ...) ===
    === mutate: running lune run test ===
      FAIL  tests/server/lobby_gate_test.luau :: Contract pin 2: a PlayerLeft outside the Lobby is ignored - a mid-round departure is ROUND-005
            C:\Users\ryanc\Projects\first-roblox\tests\server\lobby_gate_test:237: Contract pin 2: a PlayerLeft was acted on in 3 phase(s) past the Lobby (Assignment, Post, Resolution). ROUND-004 unseats in the LOBBY and nowhere else; a mid-round departure is ROUND-005's. The first:
    C:\Users\ryanc\Projects\first-roblox\tests\helpers\PhaseMachineContract:107: AC-7: a PlayerLeft naming the seated player p2, in Assignment was not ignored - the returned state differs from the one given:
    165 passed, 10 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T151142Z.74016.bak) ===

The narrowed test names all three remaining phases and quotes the first. The
tally is unchanged at 165/10 rather than rising, because the same mutation makes
this story's `AC-7: a departure to exactly min_players_to_continue leaves the
round running` pass - the unseating it needs now happens, and nothing yet
consults quorum. That is the collision PO decision 4 rules on, visible in one
run.

### Probe 2 - `Contract pin 1: a PlayerLeft in Round naming a player who is not seated is ignored`

The behaviour pinned is that a leave naming somebody NOT seated is an ordinary
ignored event even in `Round` - not a departure, and therefore not a step on
which quorum is evaluated. The mutation makes the branch unseat seat 1 outside
the Lobby whoever is named.

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/then seatOf(state, event.playerId) else nil/then seatOf(state, event.playerId) else 1/' \
        -- lune run test

    === mutate: src/server/round/PhaseMachine.luau (1 line(s) changed by s/then seatOf(state, event.playerId) else nil/then seatOf(state, event.playerId) else 1/) ===
    === mutate: running lune run test ===
      FAIL  tests/server/round_ending_test.luau :: Contract pin 1: a PlayerLeft in Round naming a player who is not seated is ignored
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\PhaseMachineContract:107: AC-7: a PlayerLeft naming never-seated-p99, in Round was not ignored - the returned state differs from the one given:
    value.players.1: expected "p1", got "p2"
    164 passed, 11 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T151159Z.76033.bak) ===

The assertion that went red names the event, the phase and the exact field that
changed. 164/11 against the clean 165/10: one test flipped, and it is this one.

### Probe 3 - the two AC-4 tests

Both are green on arrival because the machine already records a `RoundResolved`
outcome verbatim (ROUND-003 AC-3) and has no round clock to lose to. The
behaviour AC-4 pins is *the outcome recorded is the EVENT's, not the clock's*, so
the mutation makes the `RoundResolved` branch record `lost(clock)` instead.

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/resolution.outcome = event.outcome/resolution.outcome = { result = "lost", reason = "clock" }/' \
        -- lune run test

    === mutate: src/server/round/PhaseMachine.luau (1 line(s) changed by s/resolution.outcome = event.outcome/resolution.outcome = { result = "lost", reason = "clock" }/) ===
    === mutate: running lune run test ===
      FAIL  tests/server/round_ending_test.luau :: AC-4: a RoundResolved arriving on the step the clock expired records the outcome the event carried
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\RoundEndingContract:607: AC-4: the clock had expired and the event arrived on the SAME step; the outcome recorded is { reason = "clock", result = "lost" }, not the one the event carried. The event describes something that happened inside the round; the clock describes the round running out around it. The event wins
      FAIL  tests/server/round_ending_test.luau :: AC-4: a RoundResolved outranks quorum and the clock when all three hold on one step
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\RoundEndingContract:654: AC-4: all three terminal conditions held on one step and the outcome recorded is { reason = "clock", result = "lost" }, not the event's. RoundResolved is first in the precedence list (architecture.md section 3)
    161 passed, 14 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T151740Z.99433.bak) ===

161/14 against the clean 165/10: four tests flipped. Two are this story's AC-4
pair, which is the evidence. The other two are ROUND-003's frozen
`AC-3: RoundResolved moves Round to Resolution and records the outcome unchanged`
and `AC-3: an outcome of a different result is recorded just as unchanged`, which
is correct - probe 3 breaks the behaviour they own as well, and both suites
should see it.

## Handoff: RED -> GREEN

### The command

    lune run test

There is no per-file filter; the runner walks `tests/` and runs everything
(`lune/test.luau`, BOOT-001's output contract). The two files this story adds are
`tests/server/round_ending_test.luau` and
`tests/server/round_ending_controls_test.luau`.

### Where the suite stands

| | before | after |
|---|---|---|
| `lune run test` | `154 passed, 0 failed` | `165 passed, 10 failed` |

21 tests added: 13 in the real suite (10 red, 3 green on arrival and probed) and
8 controls (all green - they need no production code and RAN in RED). No
pre-existing test went red. The `unit` floor stays at 154 until GATES raises it
to the new real count.

### The failure output, verbatim

    $ lune run test
      FAIL  tests/server/round_ending_test.luau :: AC-1: the clock ends the round at exactly roundSeconds elapsed, as lost(clock), and not before
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\RoundEndingContract:303: AC-1: at now = 26 - exactly roundSeconds (20) after the Round was entered at 6 - the phase is Round. The comparison is inclusive at the boundary (architecture.md section 3)
      FAIL  tests/server/round_ending_test.luau :: AC-2: a Tick on a round already below min_players_to_continue ends it no_contest
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\RoundEndingContract:744: AC-2: a Tick at now = 7 on a round holding { 1 = "p1", 2 = "p2" } against minPlayersToContinue 3 left the machine in Round. Quorum is consulted on Tick as well as on PlayerLeft
      FAIL  tests/server/round_ending_test.luau :: AC-2: a departure that takes the count below min_players_to_continue ends the round no_contest on that step
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\RoundEndingContract:460: AC-2: p2 left a round of 4 at now = 7 and { 1 = "p1", 2 = "p2", 3 = "p3", 4 = "p4" } are seated, wanted 3. A mid-round departure unseats (Contract pin 1)
      FAIL  tests/server/round_ending_test.luau :: AC-3: a round that ended below quorum records no_contest and never lost
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\RoundEndingContract:237: AC-3: 2 player(s) left a round of 4, taking the seated count below minPlayersToContinue (3), and the machine is in Round with { 1 = "p1", 2 = "p2", 3 = "p3", 4 = "p4" } seated
      FAIL  tests/server/round_ending_test.luau :: AC-5: when the clock and quorum both fall on one step the reason is below_quorum, on every run
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\RoundEndingContract:680: AC-5: a Tick at now = 31, below quorum (2 seated against minPlayersToContinue 3) and past roundSeconds (20), left the machine in Round
      FAIL  tests/server/round_ending_test.luau :: AC-6: each of the three endings emits exactly one ComputeTrace, carrying the round id, across the ending sequence
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\RoundEndingContract:207: AC-6: a Tick at now = 26 - exactly roundSeconds (20) after the Round was entered at 6 - left the machine in Round. round_seconds elapsed ends the round
      FAIL  tests/server/round_ending_test.luau :: AC-7: a departure to exactly min_players_to_continue leaves the round running
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\RoundEndingContract:369: AC-7: p2 left a round of 4 at now = 7 and { 1 = "p1", 2 = "p2", 3 = "p3", 4 = "p4" } are seated, wanted 3. A mid-round departure unseats (Contract pin 1)
      FAIL  tests/server/round_ending_test.luau :: AC-7: a round at exactly min_players_to_continue still ends when one more player leaves
            C:\Users\ryanc\Projects\first-roblox\tests\server\round_ending_test:135: AC-7: a round held at exactly minPlayersToContinue (3) and then lost one more player is in Round at now = 8. "Below" is a threshold, not a floor the round sits on forever
      FAIL  tests/server/round_ending_test.luau :: Contract pin 2: an unrecognised event at a Round below quorum is ignored, and the next Tick ends the round
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\RoundEndingContract:929: Contract pin 2: the events above are ignored, and the NEXT Tick ends the round - it left the machine in Round with nil. Without this half, ignoring everything would satisfy the check
      FAIL  tests/server/round_ending_test.luau :: Contract pin 5: a round that already resolved is not re-resolved by a clock that expired afterwards
            C:\Users\ryanc\Projects\first-roblox\tests\helpers\RoundEndingContract:237: Contract pin 5: 2 player(s) left a round of 4, taking the seated count below minPlayersToContinue (3), and the machine is in Round with { 1 = "p1", 2 = "p2", 3 = "p3", 4 = "p4" } seated
    165 passed, 10 failed

Every one is an assertion failure naming its criterion. There is no load failure:
the module exists and the file loads, so every assertion in it ran.

### One line per test

`tests/server/round_ending_test.luau`:

| Test | Asserts | AC |
|---|---|---|
| the clock ends the round at exactly roundSeconds elapsed... | still `Round` at `roundSeconds - 0.1`; `Resolution` with `{lost, clock}` at exactly `roundSeconds` and at `roundSeconds * 3`; the seated list unchanged; the step does not mutate its input | AC-1 |
| a departure that takes the count below... | each leave unseats one; the round survives every count at or above the threshold; the crossing step is `Resolution` with `{no_contest, below_quorum}` and holds the right players; that step does not mutate its input | AC-2, AC-7 |
| a Tick on a round already below... | quorum is consulted on `Tick` too: `Resolution` with `{no_contest, below_quorum}` | AC-2 |
| a round that ended below quorum records no_contest and never lost | the quorum ending's `result` is `no_contest` and is NOT `lost`, its reason is `below_quorum`, the clock ending's result IS `lost`, and the two outcomes differ | AC-3 |
| a RoundResolved arriving on the step the clock expired... | one step, quorum intact, `now` past the clock: the outcome is the event's verbatim; the count is intact; deterministic; non-mutating | AC-4 |
| a RoundResolved outranks quorum and the clock... | one step with ALL THREE conditions true: the outcome is the event's verbatim | AC-4 |
| when the clock and quorum both fall on one step... | one step, below quorum and past the clock: reason is `below_quorum` and result is `no_contest`; identical repeat calls give identical states, effects and reason | AC-5 |
| each of the three endings emits exactly one ComputeTrace... | for the clock, quorum and event endings: exactly one `ComputeTrace` across ending step to `Post` to `Lobby`, carrying the round id; the ending step emits nothing; the whole sequence is `ComputeTrace, PromptRematch` | AC-6 |
| a departure to exactly min_players_to_continue leaves the round running | still `Round`, exactly `minPlayersToContinue` seated, no outcome, and a further `Tick` inside the clock leaves it there | AC-7 |
| a round at exactly min_players_to_continue still ends when one more leaves | "below" is a threshold, not a floor: one more departure resolves `no_contest` | AC-7, AC-2 |
| an unrecognised event at a Round below quorum is ignored... | `RematchAccepted`, an off-union kind and a leave naming nobody seated are all ignored in full at a below-quorum `Round`; the next `Tick` ends it | pin 2 |
| a round that already resolved is not re-resolved... | Resolution to Post carries the outcome unchanged even at a `now` far past the round clock; a `PlayerLeft` in `Post` is ignored | pin 5 |
| a PlayerLeft in Round naming a player who is not seated is ignored | an unseated name is an ordinary ignored event in `Round` - state unchanged, no effects, nothing raised | pin 1 |

`tests/server/round_ending_controls_test.luau`: 8 tests - the baseline, five
controls, and two records of a control that fires on more than one check. See the
control table below.

### Files touched

| File | Change |
|---|---|
| `tests/helpers/RoundEndingContract.luau` | NEW - the checks |
| `tests/helpers/RoundEndingStubs.luau` | NEW - the baseline ending machine and five controls |
| `tests/server/round_ending_test.luau` | NEW - the real suite |
| `tests/server/round_ending_controls_test.luau` | NEW - the controls suite |
| `tests/server/lobby_gate_test.luau` | narrowed, ONE test, per PO decision 4: the phase list is now `Assignment, Resolution, Post` and the comment says why. Message and structure otherwise untouched; no other frozen test changed |
| `docs/backlog/stories/ROUND-005.md` | `## Test plan`, `## Regressions`, this section |

No production file was written; `git diff -- src` is empty. No manifest change
was needed: these tests add no dependency.

### The export shape these tests already pin

Stated as fact, not as suggestion: the tests import it and a wrong guess is a
failure, not a debate.

    local PhaseMachine = require("../../src/server/round/PhaseMachine")

    PhaseMachine.initial(config, seed, roundId) -> RoundState
    PhaseMachine.step(state, event, now)        -> (RoundState, { Effect })

Both are called as dot calls on plain field functions. **No signature changes and
no new exports.** ROUND-003's `Contract: PhaseMachine exports initial and step as
plain field functions` is frozen and still green.

Fields the assertions read off a `RoundState`: `phase`, `phaseEnteredAt`,
`roundId`, `players`, `outcome`, `config`. Two of those matter more than usual
here:

- **`config` must be read off the state.** `RoundEndingContract.belowQuorumRound`
  deep-copies a machine-produced `Round` state, so the `config` it hands back is
  a structurally equal COPY. A machine that compares config by identity, or that
  reaches for `Tuning` behind the state's back, fails.
- **`outcome` is exactly two keys.** Every outcome assertion is `Deep.equal`
  against `{ result = ..., reason = ... }`, and `Deep.diff` reports an extra key
  as `unexpected`. The degraded-round flag the Contract defers is therefore
  pinned OUT by these tests, which is what the story's `## Contract` asks for.

Outcome values this story owns, pinned verbatim:

    { result = "lost",       reason = "clock" }
    { result = "no_contest", reason = "below_quorum" }

Effects: `Deep.kinds` reads `effect.kind`, and AC-6 reads `traces[1].roundId`, so
`{ kind = "ComputeTrace", roundId = ... }` is pinned unchanged from ROUND-003.
The new endings emit NO effect of their own.

**Not constrained, and deliberately left to GREEN**: the names and shapes of any
internal helper; where in `step` the branches sit; whether the clock is consulted
on the `PlayerLeft` path at all (no check combines a departure with an expired
clock, so either reading passes - `RoundEndingStubs` chooses not to, and says so
in a comment).

### Tests that passed on arrival, and what earns them

| Test | Why it was green | Earned by |
|---|---|---|
| `Contract pin 1: a PlayerLeft in Round naming a player who is not seated is ignored` | today `PlayerLeft` is ignored in every phase but the Lobby | probe 2 in `## Regressions` |
| `AC-4: a RoundResolved arriving on the step the clock expired...` | the machine already records the event's outcome verbatim and has no round clock to lose to | probe 3 |
| `AC-4: a RoundResolved outranks quorum and the clock...` | as above | probe 3 |
| `Contract pin 2: a PlayerLeft outside the Lobby is ignored` (ROUND-004, narrowed) | `PlayerLeft` is ignored outside the Lobby today | probe 1 |

### The negative controls, and the value each one MEASURED

These controls need no production code, so - unlike an ordinary RED - they RAN,
and the right-hand column is a measurement rather than a claim. All 8 control
tests are green; each fragment below is asserted by `names(...)` in
`tests/server/round_ending_controls_test.luau`, so if GREEN's machine changes
what a check reports, the control test says so.

| Control (`RoundEndingStubs`) | The one defect | Must FAIL | Measured value in RED | Must PASS |
|---|---|---|---|---|
| `ending` (baseline) | none | nothing | all 12 checks accept it | every check |
| `losing` | quorum ending recorded as `lost` | AC-3 | `the result recorded is "lost"` | the weak "the round ended" check, AC-1, AC-4, AC-6, AC-7 |
| `doubleTracing` | a `ComputeTrace` from the `Round` branch on the way out | AC-6 | `emitted 2 ComputeTrace effect(s)` | the weak "at least one ComputeTrace" check, AC-1 to AC-5, AC-7 |
| `clockFirst` | precedence reordered: `clock` before `below_quorum` | AC-5 | `the reason recorded is "clock"` | AC-1, AC-2 (both halves), AC-3, AC-4, AC-6, AC-7 |
| `atOrBelow` | `<=` where the Contract says `<` | AC-7 | `and the phase is Resolution` (at a count of exactly 3) | AC-1, AC-3, AC-5, AC-6 |
| `eventLoses` | the clock outranking a simultaneous `RoundResolved` | AC-4 (both tests) | `the outcome recorded is { reason = "clock", result = "lost" }` | AC-1, AC-2, AC-3, AC-5, AC-6, AC-7, and the two-step reading of AC-4 |

Two controls fire on more than one check, measured and recorded as their own
tests rather than discovered at acceptance:

| Control | Also fails | Measured value | Why |
|---|---|---|---|
| `atOrBelow` | AC-2 | `and the phase is already Resolution` | AC-2's check asserts the round survives every count at or above the threshold on its way down |
| `losing` | AC-2, AC-5 | `recorded result "lost", wanted "no_contest"` | both compare the whole outcome, not only the reason |

**What GREEN owes here.** These numbers were measured against the STUBS. Confirm
each one against the shipped module by running the three `## Notes` mutations
below and checking the tests that go red, and the messages they carry, against
this table. A control that measures the wrong thing makes every threshold in the
suite look calibrated and prove nothing.

### The `## Notes` mutations, predicted

The story predicts one red test per mutation. Measured against these tests, two
of the three make more than one red - the suite is stronger than the prediction,
not different from it. Run them at acceptance and expect:

| Mutation | Predicted in `## Notes` | Predicted here | Which tests |
|---|---|---|---|
| 1. `<` to `<=` | AC-7 alone | **2 red** | `AC-7: a departure to exactly min_players_to_continue leaves the round running` and `AC-2: a departure that takes the count below min_players_to_continue...` |
| 2. reorder so `clock` precedes `below_quorum` | AC-5 | **1 red** | `AC-5: when the clock and quorum both fall on one step...` |
| 3. record the quorum ending as `lost` | AC-3 | **3 red** | `AC-3: a round that ended below quorum records no_contest and never lost`, `AC-2: a departure that takes the count below...`, `AC-5: when the clock and quorum both fall on one step...` |

If mutation 3 leaves AC-3 green, AC-3 was written as "the round ended" and the
story is wrong about its own control. It is not: `RoundEndingStubs.losing` is
that implementation, and `tests/server/round_ending_controls_test.luau` watches
AC-3 refuse it in RED.

### `bash scripts/gates.sh --fast`

    --- gate summary ---
    PASS         format (0s, observed 34)
    PASS         lint (0s, observed 34, floor 1)
    PASS         typecheck (2s, observed 7)
    FAIL         unit (6s, exit 1) -> .claude/state/gate-logs/unit.log
    UNCONFIGURED coverage
    PASS         build (0s, observed 17308)

    --fast skipped: integration mutation
    1 required gate(s) failed.

Exactly the shape RED wants: the test gate red with this story's assertions, and
every gate that judges the ADMISSIBILITY of the tests green. The new files are
`stylua`-clean and `selene`-clean (`observed 34` files, up from 32). `typecheck`
reads `src` only, so it is unaffected. The first run WARNed `format` on three of
the new files; `stylua` was run over them and the second run is the one above.
Not recorded in the story - a `--fast` run is not a full run.

All timings are from a local run on this machine (Windows, Git Bash). Nothing
here is time-sensitive: every test is arithmetic over small tables with a
simulated clock, the whole suite is 6 s under the gate, and no test in this story
has a timeout of its own or needs one.

### Deferred verifications

Nothing is deferred and nothing was declined. The story's `## Deferred
verifications` block records that simultaneity is producible in RED, and it was -
see `belowQuorumRound` and the AC-4/AC-5 checks. Every control this story names
was RUN in RED, because none of them needs production code.

### What GREEN should know before starting

1. **`PlayerLeft` gains a second phase, not a general one.** `Lobby` keeps
   ROUND-004's behaviour exactly; `Round` unseats the named player and then
   evaluates quorum ON THAT STEP; `Assignment`, `Resolution` and `Post` still
   ignore it in full, and `tests/server/lobby_gate_test.luau` still pins all
   three.
2. **A leave naming somebody not seated is an IGNORED event, in `Round` too.** No
   unseating, and therefore no quorum evaluation - the state comes back
   untouched. `Contract pin 1`'s test is the one that sees this, and it is the
   test probe 2 earns.
3. **Quorum is consulted on `Tick` and on `PlayerLeft`, never at the top of
   `step`.** ROUND-003 AC-7 is frozen: a `RematchAccepted` or an off-union kind
   at a `Round` already below quorum returns the state unchanged with no
   effects, and the NEXT `Tick` is what ends the round. Both halves are asserted.
4. **The ending step emits nothing.** The single `ComputeTrace` is still emitted
   by `Resolution -> Post` (ROUND-003 AC-4, frozen and green). AC-6 counts over
   the ending step plus every step through `Post` and back to `Lobby`, and
   asserts that whole sequence is `ComputeTrace, PromptRematch`.
5. **The outcome table is exactly `{ result, reason }`.** `Deep.equal` reports an
   extra key as a difference, so the deferred degraded-round flag cannot be
   sneaked in early.
6. **Neither ending touches the seated list beyond the departure itself.** AC-1
   asserts the clock ending leaves all `playersMin` seated; AC-2 asserts the
   quorum ending holds exactly the players left after the last departure.
7. **`Resolution.phaseEnteredAt` is the `now` of the step that ended the round.**
   AC-6 steps forward from it, and ROUND-003 AC-4 already requires `Resolution`
   to move to `Post` on the next step with the clock standing still.
8. **A resolved round is not re-resolved.** Once in `Resolution` or `Post`,
   neither the clock nor quorum is consulted again, even at a `now` three round
   lengths later.
9. **Nothing in these tests constrains where the branches sit in `step`**, only
   what one call returns. Write it the way ROUND-003 and ROUND-004 wrote theirs.

---

## GREEN: control values confirmed

Every row of the handoff's two tables was re-measured **against the shipped
`src/server/round/PhaseMachine.luau`**, not merely observed green. RED measured
its controls against `tests/helpers/RoundEndingStubs.luau`; a control can pass
while measuring something else, and then every threshold calibrated against it is
decoration.

The clean baseline for every number below: `lune run test` -> **`175 passed, 0
failed`** (154 pre-existing + the 21 this story adds), against `165 passed, 10
failed` at the end of RED. No pre-existing test went red.

Every mutation went through `bash scripts/mutate.sh`, which restored the file and
verified the restore with `cmp` each time. Fixture throughout: the injected
`CONFIG` the tests use - `lobbySeconds = 3`, `postRoundSeconds = 2`,
`roundSeconds = 20`, `playersMin = 4`, `playersMax = 6`,
`minPlayersToContinue = 3`. Paths are elided to `...` for width, as elsewhere in
this story.

### The `## Notes` mutations, measured

**Mutation 1 - the quorum comparison from `<` to `<=`.** Run first, as `## Notes`
asks.

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/#state.players < state.config.minPlayersToContinue/#state.players <= state.config.minPlayersToContinue/' \
        -- lune run test
      FAIL  tests/server/round_ending_test.luau :: AC-2: a departure that takes the count below min_players_to_continue ends the round no_contest on that step
            ...\tests\helpers\RoundEndingContract:467: AC-2: 3 seated is not below minPlayersToContinue (3) and the phase is already Resolution
      FAIL  tests/server/round_ending_test.luau :: AC-7: a departure to exactly min_players_to_continue leaves the round running
            ...\tests\helpers\RoundEndingContract:375: AC-7: 3 seated is not below minPlayersToContinue (3) and the phase is Resolution. The threshold is "below", not "at or below"
    173 passed, 2 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T153142Z.7208.bak) ===

**2 red, and exactly the two tests the handoff names.** `## Notes`' prediction of
1 is the low one RED had already corrected.

**Mutation 2 - the precedence list reordered so `clock` precedes
`below_quorum`.** Expressed as a single `sed`: the quorum branch fires only while
the clock has NOT expired, so on a step where both hold the clock branch beneath
it wins. That is the reorder, and it shows up only in the `Tick` branch because
`PlayerLeft` never consults the clock (Contract pin 6).

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/if state.phase == "Round" and isBelowQuorum(state) then/if state.phase == "Round" and isBelowQuorum(state) and elapsedIn(state, now) < state.config.roundSeconds then/' \
        -- lune run test
      FAIL  tests/server/round_ending_test.luau :: AC-5: when the clock and quorum both fall on one step the reason is below_quorum, on every run
            ...\tests\helpers\RoundEndingContract:690: AC-5: the clock had expired AND the count was below minPlayersToContinue on the same step, and the reason recorded is "clock". A round nobody can play did not run out of time: the precedence is RoundResolved > below_quorum > clock (architecture.md section 3)
    174 passed, 1 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T153154Z.7726.bak) ===

**1 red, and it is AC-5.** Predicted 1. Agrees.

**Mutation 3 - the quorum ending recorded as `result = "lost"`.**

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/return { result = "no_contest", reason = "below_quorum" }/return { result = "lost", reason = "below_quorum" }/' \
        -- lune run test
      FAIL  AC-2: a Tick on a round already below min_players_to_continue ends it no_contest
            RoundEndingContract:750: the Tick ended the round below quorum and recorded { reason = "below_quorum", result = "lost" }: value.result: expected "no_contest", got "lost"
      FAIL  AC-2: a departure that takes the count below min_players_to_continue ends the round no_contest on that step
            RoundEndingContract:495: the outcome recorded is { reason = "below_quorum", result = "lost" }: value.result: expected "no_contest", got "lost"
      FAIL  AC-3: a round that ended below quorum records no_contest and never lost
            RoundEndingContract:540: AC-3: the round ended because the lobby fell below minPlayersToContinue and the result recorded is "lost". No loss is recorded and season progress is unaffected: the group did not fail, the lobby did (mechanics.md section 8)
      FAIL  AC-5: when the clock and quorum both fall on one step the reason is below_quorum, on every run
            RoundEndingContract:697: AC-5: the quorum ending recorded result "lost", wanted "no_contest" (AC-3)
      FAIL  AC-7: a round at exactly min_players_to_continue still ends when one more player leaves
            round_ending_test:143: AC-7/AC-2: the round ended with { reason = "below_quorum", result = "lost" }: value.result: expected "no_contest", got "lost"
      FAIL  Contract pin 2: an unrecognised event at a Round below quorum is ignored, and the next Tick ends the round
            RoundEndingContract:929: the NEXT Tick ends the round - it left the machine in Resolution with { reason = "below_quorum", result = "lost" }
      FAIL  Contract pin 5: a round that already resolved is not re-resolved by a clock that expired afterwards
            RoundEndingContract:868: value.result: expected "no_contest", got "lost"
    168 passed, 7 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T153206Z.8246.bak) ===

**7 red where the handoff predicted 3 - the one divergence in this section, and
it is in the safe direction.** All three predicted tests are there and each fails
with its predicted message. The extra four are `AC-2 (Tick)`, the inline `AC-7`,
`Contract pin 2` and `Contract pin 5`, and the cause is structural rather than
surprising: every one of those compares the WHOLE outcome with `Deep.equal`
against `RoundEndingContract.quorumOutcome()`, so a wrong `result` fails them as
surely as a wrong `reason` would. RED's prediction was drawn from the checks
`RoundEndingStubs.losing` is fed in the controls suite, which is a subset;
against the real machine every check that reaches a quorum ending sees the
defect. Nothing to amend - `## Notes` is orchestrator guidance, and a suite that
catches a mutant in more places than predicted is stronger than the prediction
rather than in conflict with it (`## PO ruling at RED -> GREEN`, ruling 3).

Critically, AC-3 does **not** stay green, so the story's own worry - "if it stays
green, AC-3 was written as 'the round ended'" - is now answered against the
shipped module and not only against a stub.

### The two controls no `## Notes` mutation reaches

AC-6's `doubleTracing` and AC-4's `eventLoses` have no mutation in `## Notes`, so
they are confirmed here with one probe each. Without them, two rows of the
handoff's control table would still rest on RED's stub measurement alone.

**`doubleTracing` - a `ComputeTrace` emitted from the ending step.** The
expression hits both terminal returns, so all three endings emit one on the way
out; AC-6 counts over all three.

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/return resolution, {}/return resolution, { { kind = "ComputeTrace", roundId = state.roundId } }/' \
        -- lune run test
      FAIL  tests/server/phase_machine_test.luau :: AC-8: a full lifecycle emits exactly AssignSeats, ComputeTrace, PromptRematch, in that order
            ...\tests\server\phase_machine_test:758: the lifecycle emitted { 1 = "AssignSeats", 2 = "ComputeTrace", 3 = "ComputeTrace", 4 = "PromptRematch" }, wanted { 1 = "AssignSeats", 2 = "ComputeTrace", 3 = "PromptRematch" }
      FAIL  tests/server/round_ending_test.luau :: AC-6: each of the three endings emits exactly one ComputeTrace, carrying the round id, across the ending sequence
            ...\tests\helpers\RoundEndingContract:818: AC-6: the round ended by the clock and the sequence from the ending step back to Lobby emitted 2 ComputeTrace effect(s): { 1 = "ComputeTrace", 2 = "ComputeTrace", 3 = "PromptRematch" }. Exactly one - and a machine that keeps ticking a finished round emits a second
    173 passed, 2 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T153554Z.9727.bak) ===

`emitted 2 ComputeTrace effect(s)` - the handoff's measured fragment, word for
word, now measured against the real machine. ROUND-003's frozen AC-8 goes red
alongside it, which is correct: the mutation breaks the behaviour that story owns
as well.

**`eventLoses` - the clock outranking a simultaneous `RoundResolved`.** The same
expression as RED's probe 3, re-run against the shipped module.

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/resolution.outcome = event.outcome/resolution.outcome = { result = "lost", reason = "clock" }/' \
        -- lune run test
      FAIL  AC-4: a RoundResolved arriving on the step the clock expired records the outcome the event carried
            RoundEndingContract:607: AC-4: the clock had expired and the event arrived on the SAME step; the outcome recorded is { reason = "clock", result = "lost" }, not the one the event carried...
      FAIL  AC-4: a RoundResolved outranks quorum and the clock when all three hold on one step
            RoundEndingContract:654: AC-4: all three terminal conditions held on one step and the outcome recorded is { reason = "clock", result = "lost" }, not the event's...
      FAIL  tests/server/phase_machine_test.luau :: AC-3: RoundResolved moves Round to Resolution and records the outcome unchanged
      FAIL  tests/server/phase_machine_test.luau :: AC-3: an outcome of a different result is recorded just as unchanged
    171 passed, 4 failed
    === mutate: command exited 1; restored (verified byte-for-byte against .claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T153611Z.10286.bak) ===

The same four tests RED's probe 3 flipped, with the same messages; only the
totals moved (`161/14` then, `171/4` now), because the baseline moved from
`165/10` to `175/0`. This is also the evidence that the two AC-4 tests - green on
arrival in RED - still discriminate now that the machine really does have a round
clock and a quorum they could have lost to.

### The handoff's control table, confirmed row by row

| Control (`RoundEndingStubs`) | RED's measured fragment | Reproduced against the shipped module by | Agrees? |
|---|---|---|---|
| `ending` (baseline) | all 12 checks accept it | the clean run: `175 passed, 0 failed`, all 13 real-suite tests green | yes |
| `losing` (AC-3) | `the result recorded is "lost"` | mutation 3, AC-3, verbatim | yes |
| `losing` (also AC-2, AC-5) | `recorded result "lost", wanted "no_contest"` | mutation 3, AC-5, verbatim. **AC-2 differs in wording only**: against the real machine AC-2 fails one assertion earlier, on `Deep.equal` of the whole outcome, and reports `value.result: expected "no_contest", got "lost"` | yes, with the wording noted |
| `doubleTracing` (AC-6) | `emitted 2 ComputeTrace effect(s)` | the `doubleTracing` probe above, verbatim | yes |
| `clockFirst` (AC-5) | `the reason recorded is "clock"` | mutation 2, verbatim | yes |
| `atOrBelow` (AC-7) | `and the phase is Resolution` | mutation 1, AC-7, verbatim | yes |
| `atOrBelow` (also AC-2) | `and the phase is already Resolution` | mutation 1, AC-2, verbatim | yes |
| `eventLoses` (AC-4, both) | `the outcome recorded is { reason = "clock", result = "lost" }` | the `eventLoses` probe above, verbatim in both AC-4 tests | yes |

### One aborted probe, recorded because it restored

The first attempt at the `doubleTracing` probe used an expression that appended a
`return` to an existing statement, leaving an unreachable statement after it -
invalid Luau. `lune run test` did not fail on it: it **hung**, with no output, and
was killed after about three minutes. `.claude/state/mutations/log` records the
run as `exited 137 ... restored (verified)`, so `mutate.sh` restored the file and
`cmp`-verified it even though its command was killed rather than exiting. Worth
knowing for the next agent writing a `sed` probe against this stack: a
syntactically invalid module is a hang here, not an error, so keep probe
expressions statement-shaped.

### After every probe

    $ git status --short -- src
    (only this story's modification of src/server/round/PhaseMachine.luau)
    $ ls .claude/state/mutations/
    log

No `.bak` and no `.new` remain, so every probe restored and was `cmp`-verified.
`git diff -- tests` shows only RED's own uncommitted narrowing of
`tests/server/lobby_gate_test.luau` (18 insertions, 7 deletions, PO decision 4):
GREEN wrote no test file.

### What GREEN changed in `src/server/round/PhaseMachine.luau`

One file, no signature change, no new export. `initial` and `step` keep their
ROUND-003 shapes.

- Four small helpers beside the existing ones: `clockOutcome()` and
  `quorumOutcome()`, each returning a FRESH table rather than a shared constant;
  `isBelowQuorum(state)`, the strict `<` in one place so mutation 1 has one line
  to hit; and `resolvedAs(state, outcome, now)`, which enters `Resolution`,
  writes the outcome once and returns an EMPTY effect list (Contract pin 3).
- Two branches in `onTick`, in the contract's order: `Round` and below quorum ->
  `no_contest`/`below_quorum`; then `Round` and `elapsedIn(state, now) >=
  roundSeconds` -> `lost`/`clock`. `RoundResolved` outranks both structurally, by
  arriving in its own branch that never reaches here.
- `PlayerLeft` now unseats in `Lobby` **or** `Round` and, when the state it
  produced is a `Round` below quorum, resolves on that same step. `Assignment`,
  `Resolution` and `Post` are untouched, and a leave naming somebody not seated is
  still an ignored event, in `Round` too - so quorum is not evaluated for it.
- The header: the "OUT OF SCOPE HERE ... (ROUND-005)" paragraph is replaced by
  the precedence list, why a quorum failure is not a loss, why the comparison is
  strict, why the ending step emits nothing, and why a resolved round is not
  re-resolved. The durations paragraph now also says where the count is
  consulted, and that a `PlayerLeft` step never consults the clock (pin 6).

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-16T16:23:51Z
    commit: 39c2dc9
    tree:   4710c8000685815d3efcb642582e01f1b5899b9e
    result: pass (5 ran, 3 unconfigured, 0 known)

    PASS         format (1s, observed 38)
    PASS         lint (1s, observed 38, floor 1)
    PASS         typecheck (3s, observed 7)
    PASS         unit (6s, observed 175, floor 175)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 20721)
    UNCONFIGURED mutation

## REVIEW: the PR, and its CI

**PR:** https://github.com/ryanczhang7/first-roblox/pull/7
**Commit:** `848e807`, on `story/ROUND-005-a-round-ends-on-outcome-clock-or-quorum`.

Both required checks pass.

    boundaries   pass   5s    actions/runs/35119010151
    gates        pass   44s   actions/runs/35119010087

The `gates` job's own summary, quoted from the CI log rather than from a local
run:

    --- gate summary ---
    PASS         format (0s, observed 38)
    PASS         lint (0s, observed 38, floor 1)
    PASS         typecheck (2s, observed 7)
    PASS         unit (1s, observed 175, floor 175)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 20721)
    UNCONFIGURED mutation
    All required gates passed (5 ran, 3 unconfigured, 0 known).

### `bash scripts/ci-local.sh`, and why `## Gate results` moved

It was run after the commit and **passed every step** — `selftest`, `--list`,
`--audit`, the full `gates.sh`, and `check-boundaries.sh` against `origin/main`:

    ok    gate record matches commit 848e807 (tree 4710c8000685815d3efcb642582e01f1b5899b9e)
    ...
    ci-local: every step CI runs passed locally, against base origin/main at commit 848e807.

It took over twenty minutes on this machine and wrote nothing until it finished,
which looked like a hang and was not one. Worth knowing before somebody kills it:
on this stack it buffers.

Its `gates.sh` step re-recorded `## Gate results`, which is why that block is
stamped `commit: 848e807` with no *"working tree had uncommitted changes"*
caveat, where the GATES-phase run was stamped `a292a88` with one. **The tree hash
did not move** — `4710c800…` in both — so it is the same code judged twice, the
second time from a clean tree. The later stamp is the stronger record and it is
the one kept.

### Two differences between the local runs and CI, both explained

**`unit` at 1 s on CI against 6–7 s locally.** The gate is *faster* on the
runner, not slower, so the timeout risk `--fast` exists to catch does not arise
here. Every test in this story is arithmetic over small tables against a
simulated clock; none has a timeout of its own and none needs one. No
`ci-factor` line is warranted on this evidence — one needs a per-test measurement
under the same gate, and `coverage`, the gate that usually motivates one, is
unconfigured on this stack.

**`format` and `lint` observed 34 at GATES and 38 afterwards.** Not a difference
in what the tools checked: `stylua` and `selene` walk the directory and read all
38 files in every one of those runs. The `n=` counter in the evidence command is
`git ls-files -- src tests lune`, which lists **tracked** files only, and this
story's four new test files were still untracked when the GATES-phase run was
recorded. ROUND-004 shows the same lag (`observed 30` locally, 34 on CI) for the
same reason: the counter trails by exactly the story's own new files until the
commit lands. Nothing is masked — the floor is 1 and both numbers are far above
it — but the counter is a weaker liveness assertion than it looks, because the
number it reports is not the number of files the tool read. That is a harness
defect worth a story of its own, not this one's to fix.
