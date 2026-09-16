---
id: ROUND-004
title: The lobby holds below the minimum and admits no more than the maximum
slug: the-lobby-holds-below-the-minimum-and-ad
epic: EPIC-01
type: feature
status: in-review
phase: REVIEW
branch: story/ROUND-004-the-lobby-holds-below-the-minimum-and-ad
depends_on: [ROUND-003]
required_gates: []
---

## Context

`players_min` is 4 and `players_max` is 6 — ratified in product-brief §0c R1, and
derived rather than preferred: 4 is the smallest ring in which the two-layer
puzzle has room (`loop.md` §2), and 6 is where channel contention turns the shared
signal stream from a channel into noise. A4's "target 8–12, cap 16" came from
hidden-role faction ratios that amendment 8 removed and is **withdrawn, not
scaled**.

This story teaches the phase machine those two numbers. It is deliberately
separate from `ROUND-003` because the *behaviour* is separate and each is one
clean cycle: the lifecycle advances on a clock, the lobby gates on a count.

The one non-obvious rule is the hold. **Below `players_min`, the lobby timer holds
rather than resetting.** `lobby_seconds` is a floor on lobby dwell time — time for
players to gather and socialise (A4) — not a punishment for a late fourth player.
A resetting timer means a lobby that gains and loses a player every 30 seconds
never starts, which is precisely the M6 lobby-fill risk amendment 1 was lowering
the floor to reduce.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given a lobby with `players_min − 1` players, when the clock is
  advanced well past `lobby_seconds`, then the phase is still `Lobby`.
- **AC-2** — Given that lobby, when one more player joins so the count reaches
  `players_min`, then the phase becomes `Assignment` on the next tick **without
  waiting a further `lobby_seconds`** — the elapsed lobby time already served is
  not discarded.
  *Control:* an implementation that resets `phaseEnteredAt` on every join **must**
  fail this, and must pass AC-1. A test that only asserts "it eventually starts"
  cannot tell the two apart; assert the `now` at which it starts.
- **AC-3** — Given a lobby that reached `players_min`, when a player leaves before
  `lobby_seconds` has elapsed and the count drops below `players_min`, then the
  phase stays `Lobby` past `lobby_seconds`, and when the count is restored the
  round starts on the next tick.
- **AC-4** — Given a lobby holding `players_max` players, when another
  `PlayerJoined` arrives, then the seated list still holds exactly `players_max`
  players and the surplus player is not among them.
- **AC-5** — Given a lobby, when the same `PlayerJoined` event for one player is
  applied twice, then that player appears once in the seated list.
- **AC-6** — Given a seated list, when players join and leave in any order, then
  the relative order of the remaining players is unchanged.
  *Semantics:* seat order is the order of joining. `SEAT-001` deals the ring from
  this list, so a list whose order depends on removal mechanics makes a round's
  ring depend on something nobody specified.

## Contract

Extends `src/server/round/PhaseMachine.luau` from `ROUND-003`. No new module and
**no signature change** — `step` keeps `(state, event, now) -> (state, {Effect})`,
so there is no caller list to grep.

### The rules, exactly

- **`PlayerJoined`** appends to `state.players` if the player is not already
  present and `#players < playersMax`. Otherwise the state is returned unchanged
  with an empty effect list — a rejected join is not an error (`ROUND-003` AC-7).
- **`PlayerLeft`** removes the player, preserving the order of the rest.
- **`phaseEnteredAt` is never rewritten by a join or a leave.** This is the hold,
  and it is one line. It is also the line a plausible implementation gets wrong in
  the other direction, which is why AC-2 asserts the *time* the round starts and
  not merely that it starts.
- The `Lobby → Assignment` guard is `now - phaseEnteredAt >= lobbySeconds and
  #players >= playersMin`, evaluated on every step, so a join that satisfies the
  count after the time has already elapsed starts the round on the next tick.
- **Rejecting the surplus join at the door is the machine's job**, not the
  driver's. A driver that filters is a driver that can forget.

### AMENDED AT PLANNED -> RED by the Lead PO — four pins, one of which is a correction

`ROUND-003` shipped and its tests are **frozen**. Three of the four pins below
exist because this story's Contract, written before `ROUND-003` was built, says
something that the shipped machine's frozen tests contradict. Finding that now
costs a paragraph; finding it in GREEN costs a bounce to RED.

**1. "Evaluated on every step" means NOT LATCHED — it does not mean at the top of
`step`. This is a correction, and it is load-bearing.** `## Contract` says the
`Lobby -> Assignment` guard is *"`now - phaseEnteredAt >= lobbySeconds and
#players >= playersMin`, evaluated on every step"*. Read literally that is
forbidden by a frozen `ROUND-003` test. `ROUND-003`'s Contract amendment 4, ruled
on by the Lead PO, puts every duration check **inside the branch for an event the
phase recognises — in practice `Tick`** — and this test enforces it:

    tests/server/phase_machine_test.luau
      "AC-7: an unrecognised event is ignored in every phase, even when the
       phase's duration is due"

It drives `{ kind = "NotAnEventKind" }` at `now = 9` through all five phases and
requires the state back unchanged. Its lobby is `seatedLobby()` — **four players,
which is `CONFIG.playersMin`, entered at 0, with `lobbySeconds = 3`** — so a
machine that evaluates this story's guard at the top of `step` transitions to
`Assignment` there and fails a frozen test.

Nothing is lost. The trailing clause of the Contract's own sentence already says
the intended behaviour — *"starts the round on the next **tick**"* — and so do
**AC-2** (*"becomes `Assignment` on the next tick"*) and **AC-3** (*"the round
starts on the next tick"*). The property that actually matters is that the guard
is **not latched**: the machine keeps no memory of "the timer fired once while the
lobby was short and was refused", so both halves are re-tested every time the
`Tick` branch runs. Pin that; keep the evaluation where `ROUND-003` put it.

**2. `PlayerLeft` unseats in `Lobby` and nowhere else.** `ROUND-003` ignores it in
every phase. AC-3 requires it to remove a seated player in the lobby, and no
criterion in this story says anything about a departure in any other phase —
`## Out of scope` sends the mid-round quorum rule to `ROUND-005`, which is the
story that needs the count to fall below `min_players_to_continue`. Unseating
mid-round here would ship behaviour no failing test demanded (law 1) and would
silently change the seated list *after* `AssignSeats` has already carried it,
which is the ring `SEAT-001` deals. So: in `Lobby`, remove and preserve order; in
`Assignment`, `Round`, `Resolution` and `Post`, return the state unchanged with an
empty effect list, exactly as today. `ROUND-005` adds the other half.

This is compatible with the frozen test `"AC-7: an event naming a player who was
never seated is ignored"`, which applies a `PlayerLeft` for `never-seated-p99` to
a seated lobby: a player who is not in the list is still a no-op after this story.

**3. A rejected join is indistinguishable from any other ignored event.** AC-4 and
AC-5 both describe refusals — the lobby is full, or the player is already seated —
and `ROUND-003` AC-7 already fixes what a refusal looks like: **the same state
back, deep-equal to the input, and an empty effect list**, with nothing raised and
nothing mutated. RED should assert AC-4 and AC-5 through the existing
`tests/helpers/PhaseMachineContract.luau` `eventIsIgnored` check rather than
writing a third spelling of "nothing happened", and then add AC-4's own assertion
about **who** is in the list. `ROUND-003`'s frozen `"AC-7: a duplicate
PlayerJoined does not seat the same player twice"` is already exactly AC-5 applied
to a four-player lobby; this story's AC-5 test is the one that must still hold
when the lobby is *not* at a boundary.

**4. Removal preserves order because it is a removal, not a swap.** AC-6's
*"relative order of the remaining players is unchanged"* means the seated list is
always a **subsequence of the join order**. The plausible wrong implementation is
the fast one — copy the last element over the removed index and shorten — which is
a correct *set* operation and scrambles the ring. AC-6 exists to catch exactly
that, so RED writes the removal test against a list long enough for a swap to be
visible (removing from the middle of five is the minimum that distinguishes them;
removing the last element distinguishes nothing).

### Callers of every changed signature

**None, and there is no grep to run, because no signature changes.** This story
extends the body of `PhaseMachine.step`; `initial` and `step` keep the shapes
`ROUND-003` pinned and every caller — the four test files under `tests/server/` —
calls them the same way before and after. RED's handoff states it re-checked this
against the tree rather than repeating the claim.

**What RED must additionally confirm, and it is not optional:** `ROUND-003`'s 54
tests are frozen and must stay green. A RED run for this story is *not* "every
test fails"; it is "the new tests fail and the 137 existing ones still pass". If
adding a criterion here turns a `ROUND-003` test red, that is a collision to
report, not a number to accept.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1..AC-4 | **Settled** | 4 and 6 are derived and ratified (`tuning.md` §1, product-brief §0c R1). Read them out through `RoundConfig`; do not pick numbers, and do not hard-code 4 or 6 in a test where the config value belongs. |
| AC-2 | **Settled, with a control** | The control distinguishes hold from reset. It is the only criterion here a wrong implementation passes half of. |
| AC-5, AC-6 | **Mechanical** | Pin exactly. |

## Deferred verifications

<!-- Nothing is deferred. The template requires this section only when a
     verification provably cannot run in the phase that wants it, and says
     to omit it otherwise - so the word "None" in prose here reads to
     check-boundaries.sh as a deferred entry with no owner and no result,
     which is the same defect as a WAIVED with no reason.
     Planned text was: None.
-->

## Model guidance

**Resolved model of every dispatch, by name:**

| Phase | Agent | Model as configured | Resolved model |
|---|---|---|---|
| orchestration | lead-po | `opus` | `claude-opus-5` (this session) |
| RED | test-developer | `opus` | `claude-opus-5` (no override at dispatch) |
| GREEN, GATES | feature-developer | `opus` | `claude-opus-5` (no override at dispatch) |

Brief RED that AC-1–AC-4's numbers are **settled** — they were derived by the Game
Designer from channel contention and ring length, and ratified by the Lead PO.
There is nothing to calibrate. The single oracle-free judgement is how AC-2's
control is phrased so that a resetting implementation cannot pass it.

## Out of scope

- Matchmaking, queueing, or what happens to the rejected surplus player. There is
  no server list and no lobby browser; a rejected join simply is not seated.
- Private servers (A6, product-brief §0c R5). A product decision, M5.
- The mid-round quorum rule. `ROUND-005`.
- Seat assignment from the seated list. `SEAT-001`.
- Any player-facing feedback about a full lobby. No UI exists.

## Game design

Implements `tuning.md` §1's `players_min` (4, derived) and `players_max` (6,
derived) and `loop.md` §2's derivation of the band.

The decision AC-2 protects is **M6's lobby-fill risk**, which the brief names as
the highest-risk assumption in the plan. A 4-player floor roughly halves the
concurrent-player density a round needs; a resetting lobby timer would give a
chunk of that back for no design benefit.

Note for M3: `players_max` 6 is derived but its **exact boundary is soft** —
`playtest.md: P-N` reads where channel contention actually bites. If that playtest
moves the number, it moves in `tuning.md` and then in `ROUND-002`'s module, and
this story's tests should still pass unchanged. If they do not, a test hard-coded
a number instead of reading the config.

## Notes

**Mutation the orchestrator should run at acceptance:**

1. Make `PlayerJoined` set `phaseEnteredAt = now`. Predicted: AC-2 goes red,
   AC-1 stays green. This is the hold-versus-reset mutation and it is the one
   assertion in the story that a weak test would miss.
2. Remove the `#players < playersMax` check. Predicted: AC-4 goes red.
3. Change the duplicate-join guard to always append. Predicted: AC-5 goes red.

**Raise the `unit` floor** to the new real count.

---

## PO decisions at PLANNED -> RED

**1. The required gate is `unit`, and it already reads this story's source.**
`ROUND-003` added `covers | unit | src/server/**` and `discovery | server` to
`.claude/harness/project.conf`, so unlike that story this one starts with the
test gate already declaring it reads `src/server/round/`. Confirmed against
`gates.sh --list`; nothing to add to `required_gates`.

**2. The epic's done-when needs nothing extra from this story.** `EPIC-01`
promises *"a lobby that refuses to start below `players_min`"* — that is exactly
AC-1 — plus a round ending by clock, by outcome event and by quorum loss, all
three of which are `ROUND-005`, the next and last story in the epic. There is no
gap between `ROUND-003` and this story for this story to absorb. Checked, not
skipped.

**3. Four Contract pins, one of them a correction to this story's own Contract.**
In `## Contract` above. The correction matters enough to restate here: *"evaluated
on every step"* was written before `ROUND-003` existed and, read literally, breaks
a frozen `ROUND-003` test. It means *not latched*, and the evaluation stays in the
`Tick` branch. No acceptance criterion changes — AC-2 and AC-3 both already say
"on the next tick" — so there is no `## Amendments` entry.

**4. RED runs the whole suite, not just its own tests.** `ROUND-003`'s 137 tests
are frozen and stay green. The `unit` floor is at **137**; a RED run here shows
the new tests failing *underneath* an otherwise intact suite, and a `ROUND-003`
test going red is a collision to report rather than a number to write down. The
floor rises to the new real count in GATES, by the Lead PO, once it is measured.

**5. The toolchain is not on this session's `PATH`** — the stale-shell symptom
`environment.md` records, not a broken install. Every dispatch and every gate run
here is prefixed with `export PATH="$HOME/.rokit/bin:$PATH"`, and every subagent
dispatch carries that line. Without it `lune run test` is `command not found`,
which a subagent could easily read as a broken test command and work around.

---

## PO ruling at RED -> GREEN

**RED is accepted.** `lune run test` → `147 passed, 7 failed`, verified by the
orchestrator rather than taken on report: all seven failures are in
`lobby_gate_test.luau`, each naming its criterion and the missing behaviour, and
**no `ROUND-003` test went red**. `gates.sh --fast` gives `format` PASS (30),
`lint` PASS (30), `typecheck` PASS (7), `build` PASS, `unit` FAIL only — the tests
are admissible. `git diff -- src` is empty and `.claude/state/mutations/` holds
only its log, so all three probes restored.

**No Contract amendment was needed**, which is the PLANNED -> RED pins doing their
job: RED reports it wrote the tests to pin 1 from the start, and nothing in the
suite drives a non-`Tick` event expecting a duration to fire.

### The assert-truncation finding, reproduced independently and sharpened

RED reported that Luau truncates an `assert` message "at roughly 500 characters"
and rewrote two messages because of it. That is a claim about a mechanism, and a
repository-wide one, so it was reproduced on a different input and without reusing
RED's code — `string.rep("A", n)` through `pcall(function() assert(false, msg) end)`
under `lune run`:

    message   400 chars -> err   444 chars,   401 A's kept
    message   480 chars -> err   524 chars,   481 A's kept
    message   500 chars -> err   544 chars,   501 A's kept
    message   520 chars -> err   555 chars,   512 A's kept
    message   600 chars -> err   555 chars,   512 A's kept
    message  2000 chars -> err   555 chars,   512 A's kept

Confirmed, and the number is sharper than "roughly 500": the cap is **exactly 512
characters of message** — a fixed buffer, not a soft limit — and the `path:line:`
prefix is *additional*, not counted against it. RED's own diagnosis was right and
its remedy was right.

**Recorded in `docs/wiki/stack.md` §3** rather than left in a test comment, as the
rule for the whole repository, with the consequence spelled out: this project has
no coverage gate, so an assertion's message carries a disproportionate share of
how a defect gets diagnosed, and the house style of long explanatory messages puts
the values at the end — exactly where they are lost. **Numbers first, essay
second.**

### AC-2's central assertion was not observed failing against the real machine

RED flagged this rather than papering over it, which is the right call and it is
accepted on these grounds. The assertion — that the round starts at the `now` the
held time implies, rather than one `lobbySeconds` later — cannot currently fail
against the shipped machine, because the machine has no count gate at all, so the
three-player lobby is already in `Assignment` and the test dies on its **AC-1
precondition**. The test is red today; it is the wrong red.

What earns it is the control the criterion itself names: `LobbyGateStubs.resetting`
fails that assertion, with measured values (`phaseEnteredAt = 9` where 0 is
correct; `Lobby` at 9.75 and `Assignment` at 12 where `Assignment` at 9.75 is
correct), and passes AC-1 — which is the half that stops the control being a stub
that fails everything. That is the same shape as `ROUND-003`'s AC-6 and AC-7
controls, and it is the shape `rules.md` allows.

**GREEN's obligation, therefore, is specific:** confirm this assertion goes green
**for the right reason** — that the measured `phaseEnteredAt` is still 0 and the
transition lands at 9.75 — and not merely that the test stopped failing. A machine
that restamps on join *and* has a count gate would also stop failing the
precondition.

### RED's corrections to the story's mutation predictions

`## Notes` predicted mutation 1 → "AC-2 red, AC-1 green" and mutation 3 → AC-5
alone. RED predicts **3** and **2**, and gives reasons rather than numbers: AC-3
also depends on the hold, because the join that restores the count restamps too;
and mutation 3 additionally trips `ROUND-003`'s frozen duplicate-join test, which
RED **observed** in probe 2 (`145 passed, 9 failed` against a `147 passed, 7 failed`
baseline). The predictions in the handoff supersede the ones in `## Notes`. The
orchestrator runs one at acceptance and compares against the handoff's list, not
the count alone.

### Dispatch model, resolved

`test-developer`, declared `model: opus` in `.claude/agents/test-developer.md`,
dispatched with no model override, resolved to **`claude-opus-5`**.

## PO acceptance at GREEN -> GATES

### Two single-assertion mutations, run by the orchestrator, both exact

GREEN ran the story's mutation 1 and measured 3 failures against RED's predicted
3. The orchestrator ran the two whose predicted catch is a **single** assertion,
which is where a vacuous test hides and where a matching count proves most.

**Mutation 2 — neutralise the `playersMax` cap.** Predicted: AC-4 alone.

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's/or #state.players >= state.config.playersMax/or false/' -- lune run test

    === mutate: src/server/round/PhaseMachine.luau (1 line(s) changed) ===
    153 passed, 1 failed
      FAIL  tests/server/lobby_gate_test.luau :: AC-4: a join into a lobby holding players_max leaves exactly players_max seated and the surplus player unseated
    === mutate: command exited 1; restored (verified byte-for-byte) ===

**Mutation 4 — removal by copying the last element over the hole**, the defect
Contract pin 4 exists for and the one a *set*-shaped implementation gets wrong
while staying correct about membership. Predicted: AC-6 alone.

    $ bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
        's|table.remove(remaining.players, seat)|remaining.players[seat] = remaining.players[#remaining.players]; remaining.players[#remaining.players] = nil|' \
        -- lune run test

    === mutate: src/server/round/PhaseMachine.luau (1 line(s) changed) ===
    153 passed, 1 failed
      FAIL  tests/server/lobby_gate_test.luau :: AC-6: joins and leaves in any order leave the seated list a subsequence of the join order
    === mutate: command exited 1; restored (verified byte-for-byte) ===

Predicted 1, measured 1, both times, and both times the named test. The suite is
`154 passed, 0 failed` after the restores and `.claude/state/mutations/` holds
only its log.

**A note on the first attempt, because it is the script earning its place.** The
cap's `or` clause is on its own line inside a multi-line `if`, so the obvious
one-line expression matched nothing:

    mutate: the expression changed nothing in src/server/round/PhaseMachine.luau.
      A probe that does not alter behaviour cannot show a test discriminates:
      the command would have passed for the same reason it passes now.

Exit 3, nothing run. Done by hand with `sed -i`, that attempt would have left the
file untouched, the suite green, and an orchestrator convinced it had probed
something. Re-targeted at the clause as written, it landed.

### The AC-2 right-reason check, which was GREEN's specific obligation

The PO ruling at RED -> GREEN flagged that AC-2's central assertion had never been
observed failing against the real machine — only against `LobbyGateStubs.resetting`
— because in RED the test died on its AC-1 precondition. GREEN was told to confirm
it goes green **for the right reason** and measured:

    held at now = 9, 3 seated : phase = Lobby, phaseEnteredAt = 0
    p4 joins at now = 9       : phaseEnteredAt = 0     <- the join did NOT restamp
    tick at now = 9.75        : phase = Assignment, phaseEnteredAt = 9.75
    9 + lobbySeconds          : 12                     <- where a restamping machine starts

The held time survives and the round starts at 9.75, not 12. The orchestrator's
own mutation 1 run through GREEN corroborates it from the other side: restamping
on join fails those tests by name.

### Control values

GREEN re-drove every control against the shipped machine and reported **no
divergence on any row**, and additionally re-drove the stubs to confirm RED's
"wrong" column reproduces. Recorded in `## GREEN: control values confirmed`.

### The `unit` floor is raised, in the story that earned it

`floor | unit | 137` → **154**, measured from this story's own runs (`154 passed,
0 failed`, `observed 154` in the gate summary). With `coverage` unconfigured on
this stack the floor is the only thing that notices a suite quietly shrinking, so
it moves in the story that added the tests.

### Dispatch model, resolved

`feature-developer`, declared `model: opus` in
`.claude/agents/feature-developer.md`, dispatched with no model override,
resolved to **`claude-opus-5`**.

## Test plan

Four new files, all test-classified. Nothing under `src/**`, no config, no
manifest — this story needed no test dependency.

| File | What it is |
|---|---|
| `tests/server/lobby_gate_test.luau` | 10 tests, the criteria applied to the real `src/server/round/PhaseMachine.luau` |
| `tests/server/lobby_gate_controls_test.luau` | 7 tests, the same checks applied to deliberately wrong lobbies |
| `tests/helpers/LobbyGateContract.luau` | AC-1..AC-6 written once as checks over a *machine*, so the real suite and the controls exercise the same objects |
| `tests/helpers/LobbyGateStubs.luau` | the baseline lobby and the five one-defect lobbies the controls aim at |

`tests/server/phase_machine_test.luau` and the three `ROUND-003` helpers are
**untouched**. The refusal checks reuse `PhaseMachineContract.eventIsIgnored` and
`PhaseMachineContract.stepDoesNotMutateItsInput`, and every comparison goes
through `Deep.equal` / `Deep.diff`, so there is no third spelling of "nothing
happened".

### Every threshold is read out of the injected config

No assertion in any of the four files writes `4` or `6`. `playersMin`,
`playersMax` and `lobbySeconds` are read from the `CONFIG` table the machine is
handed, and the derived quantities (`playersMin - 1`, `playersMax + 1`,
`lobbySeconds * 5`, `lobbySeconds / 4`) are computed from it. The two places that
need a *shape* rather than a value say so in an explicit precondition assert that
names what to do if the design stops supplying it:

- AC-5 needs a seat count **strictly between** the thresholds, so that neither
  the count gate nor the cap can be what refused the duplicate. It asserts
  `playersMin + 1 < playersMax` and, if that fails, says this is an
  `## Amendments` question rather than a number to edit in a test.
- AC-6 needs **five seats** for a removal from the middle of five to be
  distinguishable from a swap-with-the-last. It asserts `playersMax >= 5`, with
  the same instruction.

If playtest P-N moves `players_max` anywhere at or above 5 these tests pass
unchanged, which is what `## Game design`'s M3 note asks for.

### AC to test

| AC | Test | Why the assertion discriminates |
|---|---|---|
| AC-1 | `AC-1: a lobby one short of players_min stays in Lobby however far the clock runs` | `playersMin - 1` seated, ticked at `lobbySeconds * 5`. Asserts the phase **and** an empty effect list: a machine that emits `AssignSeats` for a round it did not start hands the driver a ring of three. |
| AC-1 (zero) | `AC-1: an empty lobby is still in Lobby well past lobbySeconds and has emitted nothing` | The `0` end of zero/one/many, and the case a count gate written as `#players > 0` would pass. |
| AC-2 | `AC-2: reaching players_min starts the round on the next tick, without serving another lobbySeconds` | Holds 3 players to `now = 9`, seats the fourth at `9`, ticks at `9.75`. Asserts `phase == "Assignment"` **and** `phaseEnteredAt == 9.75` **and** that the post-join lobby still records `phaseEnteredAt == 0`. A resetting implementation reaches `Assignment` at `12`, so "it eventually starts" is true of it and every assertion here is false of it. The fixture asserts `9.75 < 9 + lobbySeconds` up front, so the test cannot silently stop distinguishing hold from reset. |
| AC-2 (direct) | `AC-2: a PlayerJoined never rewrites phaseEnteredAt, whatever the now` | The same property stated on the field, over four joins at `0, 7, 11.5, 27`. **Green on arrival** — earned by probe 1 below. |
| AC-3 | `AC-3: a departure below players_min holds the lobby, and restoring the count starts the round on the next tick` | Four halves, and they fail for different reasons: the leave must unseat at all; the short lobby must hold past `lobbySeconds`; the restored lobby must start on the next tick (the hold again, arrived at by a different route); and `phaseEnteredAt` must survive both the leave and the rejoin. |
| AC-4 | `AC-4: a join into a lobby holding players_max leaves exactly players_max seated and the surplus player unseated` | Length, then **who**, then the whole list, then `eventIsIgnored`. The `who` assertion is the one that matters: `LobbyGateStubs.evicting` is exactly `playersMax` long afterwards and a length check is green for it. |
| AC-5 | `AC-5: the same PlayerJoined applied twice seats that player once, in a lobby at neither threshold` | Counts **occurrences** of the newcomer, not membership, in a lobby of 5 against `playersMin` 4 and `playersMax` 6, so only the duplicate guard can be what refused it. `ROUND-003`'s frozen version of this sits at exactly `playersMin`. **Green on arrival** — earned by probe 2 below. |
| AC-6 | `AC-6: joins and leaves in any order leave the seated list a subsequence of the join order` | Eleven steps that remove from the **middle** of five (`p3` out of `p1..p5`), then from the **front** of five, then from the back — the last distinguishes nothing and the comment says so. Two assertions: the exact list, and the general subsequence property. Measured: a swap-with-the-last implementation produces `[p6 p2 p5 p4 p8]` against the wanted `[p2 p4 p5 p6 p8]` — the right *set*, the wrong ring. Never seats more than five, so AC-4's cap is not what shapes the result. |
| purity | `AC-3/AC-6: a PlayerLeft that unseats a player does not mutate the state it was given` | `ROUND-003` AC-6 applied to the path this story adds. The non-mutation check runs first and the removal assertion runs second, because a step that does nothing at all satisfies a non-mutation check vacuously. |
| non-goal | `Contract pin 2: a PlayerLeft outside the Lobby is ignored - a mid-round departure is ROUND-005` | Pins `## Contract` pin 2 from the other side, so GREEN cannot ship a mid-round unseat that no criterion here demanded. **Green on arrival** — earned by probe 3 below. |

### The controls, and what each one proves

All seven run in `tests/server/lobby_gate_controls_test.luau`, and every one of
them **passed in RED**: these are measurements, not claims. Each wrong lobby is
`LobbyGateStubs.holding` with exactly one thing changed, and each control asserts
**both** halves — the checks it passes and the check it fails. The "passes"
half is what stops a control being a stub that fails everything, and AC-2's
criterion names it in as many words.

| Control | Passes | Fails | The trap it closes |
|---|---|---|---|
| `holding` (baseline) | AC-1..AC-6 and the non-mutation check | — | makes every failure below attributable to one line |
| `resetting` | AC-1, AC-4, AC-5, AC-6 | **AC-2** | the implementation AC-2's criterion names |
| `evicting` | AC-1, AC-2, and a bare length check | **AC-4** | "exactly `players_max` seated" is true of an implementation that threw somebody out |
| `reseating` | AC-1, AC-6 | **AC-5** | — |
| `swapping` | AC-1, AC-2, AC-4, and a written-out **set** check | **AC-6** | a correct set removal that scrambles the ring |
| `mutatingRemover` | **AC-6**, including the subsequence assertion | the non-mutation check | a leave whose visible output is correct in every respect |

`tests/server/lobby_gate_controls_test.luau` also carries
`AC-2 control: the resetting lobby does start a round eventually, which is why
AC-2 asserts the now`, which measures the half a weaker test would miss: the
resetting lobby is in `Lobby` at `9.75` and in `Assignment` at `12`.

---

## Regressions

Three assertions were **green on arrival**, because `ROUND-003` is merged and the
machine already does part of what this story asks. A test that has never been
observed to fail is not a test, so each is earned by a reverted mutation of the
specific production behaviour it claims to pin, through `scripts/mutate.sh` —
which restores the file and verifies the restore with `cmp`. `git diff -- src`
is empty and no `.bak` remains under `.claude/state/mutations/`.

**Baseline before every probe:** `147 passed, 7 failed`.

### Probe 1 — the join restamps `phaseEnteredAt` (the story's mutation 1)

Earns `AC-2: a PlayerJoined never rewrites phaseEnteredAt, whatever the now`.

```
bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
  's|\t\ttable.insert(seated.players, event.playerId)|\t\ttable.insert(seated.players, event.playerId)\n\t\tseated.phaseEnteredAt = now|' \
  -- lune run test
```

```
  FAIL  tests/server/lobby_gate_test.luau :: AC-2: a PlayerJoined never rewrites phaseEnteredAt, whatever the now
        C:\Users\ryanc\Projects\first-roblox\tests\server\lobby_gate_test:144: AC-2: seating p2 at now = 7 moved phaseEnteredAt from 0 to 7. The lobby timer HOLDS: the elapsed lobby time already served is never discarded by a join, or a lobby that gains and loses a player every thirty seconds never starts (M6)
146 passed, 8 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T005316Z.2679090.bak) ===
```

Exactly one new failure, and it is the assertion being earned. Every one of
`ROUND-003`'s 137 tests stayed green: `seatedLobby()` joins at `now = 0`, so the
restamp is a no-op for them — which is precisely why this story needs its own
test for it.

### Probe 2 — the duplicate-join guard always appends (the story's mutation 3)

Earns `AC-5: the same PlayerJoined applied twice seats that player once, in a
lobby at neither threshold`.

```
bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
  's/ or isSeated(state, event.playerId)//' -- lune run test
```

```
  FAIL  tests/server/lobby_gate_test.luau :: AC-5: the same PlayerJoined applied twice seats that player once, in a lobby at neither threshold
        C:\Users\ryanc\Projects\first-roblox\tests\helpers\LobbyGateContract:368: AC-5: the same PlayerJoined for p5 was applied twice and p5 appears 2 time(s): { 1 = "p1", 2 = "p2", 3 = "p3", 4 = "p4", 5 = "p5", 6 = "p5" }. Seating one player twice puts them in two seats of the same ring
  FAIL  tests/server/phase_machine_test.luau :: AC-7: a duplicate PlayerJoined does not seat the same player twice
        C:\Users\ryanc\Projects\first-roblox\tests\helpers\PhaseMachineContract:107: AC-7: a PlayerJoined for a player already seated was not ignored - the returned state differs from the one given:
145 passed, 9 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T005352Z.2681279.bak) ===
```

Two new failures. `ROUND-003`'s frozen duplicate test going red as well is
expected — it pins the same rule at exactly `playersMin` — and the point of this
story's version is the seat count it fires at: 5, with `playersMin` 4 and
`playersMax` 6, so neither threshold can be the reason.

### Probe 3 — `PlayerLeft` unseats in every phase

Earns `Contract pin 2: a PlayerLeft outside the Lobby is ignored - a mid-round
departure is ROUND-005`. The branch does not exist yet, so the mutation inserts
an unconditional one ahead of the `SeatsAssigned` branch.

```
bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
  's|\tif event.kind == "SeatsAssigned" then|\tif event.kind == "PlayerLeft" then local gone = copyOf(state) for i, id in gone.players do if id == event.playerId then table.remove(gone.players, i) break end end return gone, {} end\n\tif event.kind == "SeatsAssigned" then|' \
  -- lune run test
```

```
  FAIL  tests/server/lobby_gate_test.luau :: Contract pin 2: a PlayerLeft outside the Lobby is ignored - a mid-round departure is ROUND-005
        C:\Users\ryanc\Projects\first-roblox\tests\server\lobby_gate_test:226: Contract pin 2: a PlayerLeft was acted on in 4 phase(s) past the Lobby (Assignment, Post, Resolution, Round). ROUND-004 unseats in the LOBBY and nowhere else; a mid-round departure is ROUND-005's. The first:
C:\Users\ryanc\Projects\first-roblox\tests\helpers\PhaseMachineContract:107: AC-7: a PlayerLeft naming the seated player p2, in Post was not ignored - the returned state differs from the one given:
value.players.2: expected "p2", got "p3"
148 passed, 6 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T005429Z.2683372.bak) ===
```

All four phases past the Lobby are named. The run also shows the other side of
the mutation and it is worth carrying into GREEN: `AC-3/AC-6: a PlayerLeft that
unseats a player does not mutate the state it was given` and `AC-6: joins and
leaves in any order...` both went **green** under it, because an ordered,
copying removal is the right answer — it is only the *scope* that is wrong. All
137 `ROUND-003` tests stayed green, including `AC-7: an event naming a player who
was never seated is ignored`, which the mutation leaves a no-op.

---

## Handoff: RED -> GREEN

### The command

```
export PATH="$HOME/.rokit/bin:$PATH"     # this shell predates the Rokit install
lune run test
```

`lune run test -- --list` reports **154 tests** (was 137). There is no
file-level filter; the runner walks `tests/` and runs everything.

### The verbatim failure output

`147 passed, 7 failed`, exit 1. All seven failures are in
`tests/server/lobby_gate_test.luau`; **no `ROUND-003` test went red**, and the
137 frozen tests are intact.

```
  FAIL  tests/server/lobby_gate_test.luau :: AC-1: a lobby one short of players_min stays in Lobby however far the clock runs
        ...\tests\helpers\LobbyGateContract:119: AC-1: 3 player(s) is one short of playersMin (4), and at now = 15 - 5 times lobbySeconds (3) since the Lobby was entered at 0 - the phase is Assignment. The clock is a FLOOR on lobby dwell time, not the only condition for starting a round
  FAIL  tests/server/lobby_gate_test.luau :: AC-1: an empty lobby is still in Lobby well past lobbySeconds and has emitted nothing
        ...\tests\server\lobby_gate_test:100: AC-1: a lobby seating nobody is in Assignment at now = 15, with lobbySeconds = 3 and playersMin = 4
  FAIL  tests/server/lobby_gate_test.luau :: AC-2: reaching players_min starts the round on the next tick, without serving another lobbySeconds
        ...\tests\helpers\LobbyGateContract:162: AC-2 (precondition, AC-1): at now = 9 with 3 player(s) the phase is Assignment; the lobby must still be holding when the last player arrives or there is no held time to discard
  FAIL  tests/server/lobby_gate_test.luau :: AC-3/AC-6: a PlayerLeft that unseats a player does not mutate the state it was given
        ...\tests\helpers\LobbyGateContract:478: AC-3/AC-6: the leave returned { 1 = "p1", 2 = "p2", 3 = "p3", 4 = "p4" } from a lobby of 4; p2 was seated and must be gone. A step that does not mutate its input because it does nothing at all satisfies the check above vacuously, and this is the assertion that stops it
  FAIL  tests/server/lobby_gate_test.luau :: AC-3: a departure below players_min holds the lobby, and restoring the count starts the round on the next tick
        ...\tests\helpers\LobbyGateContract:231: AC-3: p2 left a lobby of 4 at now = 1.5 and 4 player(s) are seated: { 1 = "p1", 2 = "p2", 3 = "p3", 4 = "p4" }. A player who leaves the LOBBY is unseated (Contract pin 2; a departure in any other phase is ROUND-005 and stays ignored)
  FAIL  tests/server/lobby_gate_test.luau :: AC-4: a join into a lobby holding players_max leaves exactly players_max seated and the surplus player unseated
        ...\tests\helpers\LobbyGateContract:306: AC-4: p7 joined a lobby already holding playersMax (6) and 7 player(s) are now seated: { 1 = "p1", 2 = "p2", 3 = "p3", 4 = "p4", 5 = "p5", 6 = "p6", 7 = "p7" }. Rejecting the surplus join at the door is the machine's job, not the driver's
  FAIL  tests/server/lobby_gate_test.luau :: AC-6: joins and leaves in any order leave the seated list a subsequence of the join order
        ...\tests\helpers\LobbyGateContract:450: AC-6: the seated list is [p1 p2 p3 p4 p5 p6 p7 p8], wanted [p2 p4 p5 p6 p8]; removal preserves join order (Contract pin 4).
The sequence was:
join p1 -> [p1]
join p2 -> [p1 p2]
join p3 -> [p1 p2 p3]
join p4 -> [p1 p2 p3 p4]
join p5 -> [p1 p2 p3 p4 p5]
leave p3 -> [p1 p2 p3 p4 p5]
join p6 -> [p1 p2 p3 p4 p5 p6]
leave p1 -> [p1 p2 p3 p4 p5 p6]
join p7 -> [p1 p2 p3 p4 p5 p6 p7]
leave p7 -> [p1 p2 p3 p4 p5 p6 p7]
join p8 -> [p1 p2 p3 p4 p5 p6 p7 p8]
147 passed, 7 failed
```

(The absolute paths are elided to `...` for width; the runner prints them in
full.)

### `gates.sh --fast`

```
PASS         format (0s, observed 30)
PASS         lint (1s, observed 30, floor 1)
PASS         typecheck (3s, observed 7)
FAIL         unit (24s, exit 1) -> .claude/state/gate-logs/unit.log
UNCONFIGURED coverage
PASS         build (1s, observed 15638)
```

The shape RED wants: the `unit` gate fails **with the assertions above**, not
with a config error, a timeout or a lint rule the new files trip. `format`,
`lint`, `typecheck` and `build` are all green, so the tests are admissible to the
gates that will judge them. `stylua --check src tests lune` and
`selene src tests lune` are both clean on their own (`0 errors, 0 warnings`).

Timing note: all of these are **local** measurements on this machine. The `unit`
gate takes 24 s wall for 154 tests. Nothing in these files has a timeout, a
clock, a sleep or an I/O path — every test is arithmetic over tables on an
injected clock — so there is no CI-only cost to budget for.

### One line per test

`tests/server/lobby_gate_test.luau` (10):

| Test | Asserts | AC |
|---|---|---|
| `AC-1: a lobby one short of players_min stays in Lobby however far the clock runs` | phase is `Lobby` and effects are empty at `now = lobbySeconds * 5` with `playersMin - 1` seated | AC-1 |
| `AC-1: an empty lobby is still in Lobby well past lobbySeconds and has emitted nothing` | the same at zero players | AC-1 |
| `AC-2: reaching players_min starts the round on the next tick, without serving another lobbySeconds` | `Assignment` at `9.75`, `phaseEnteredAt == 9.75`, post-join lobby still `phaseEnteredAt == 0`, one `AssignSeats` | AC-2 |
| `AC-2: a PlayerJoined never rewrites phaseEnteredAt, whatever the now` | `phaseEnteredAt` unchanged across joins at `0, 7, 11.5, 27` | AC-2 |
| `AC-3: a departure below players_min holds the lobby, and restoring the count starts the round on the next tick` | leave unseats, short lobby holds past `lobbySeconds`, restore starts on the next tick, `phaseEnteredAt` survives both | AC-3 |
| `AC-4: a join into a lobby holding players_max leaves exactly players_max seated and the surplus player unseated` | length, the surplus absent, the whole list unchanged, and the refusal indistinguishable from any ignored event | AC-4 |
| `AC-5: the same PlayerJoined applied twice seats that player once, in a lobby at neither threshold` | the newcomer occurs once, the list is unchanged, no effects, and the refusal is an ordinary ignore | AC-5 |
| `AC-6: joins and leaves in any order leave the seated list a subsequence of the join order` | the exact list `[p2 p4 p5 p6 p8]`, and the subsequence property against the join order | AC-6 |
| `AC-3/AC-6: a PlayerLeft that unseats a player does not mutate the state it was given` | input deep-equal to its snapshot after the call, and the removal actually happened | AC-3, `ROUND-003` AC-6 |
| `Contract pin 2: a PlayerLeft outside the Lobby is ignored - a mid-round departure is ROUND-005` | `eventIsIgnored` in `Assignment`, `Round`, `Resolution`, `Post` | `## Contract` pin 2 |

`tests/server/lobby_gate_controls_test.luau` (7): the baseline, the four
criterion-named controls, the purity control, and the "it does eventually start"
half of AC-2's control. All seven pass.

### The export shape these tests already pin

Stated as fact, not suggestion: a test already imports it, and a wrong guess is
a load failure rather than a puzzle.

- `require("../../src/server/round/PhaseMachine")` returns a table with
  `initial` and `step` as **plain field functions**, dot-called:
  `PhaseMachine.step(state, event, now)`. No colon calls, no metatable.
- `PhaseMachine.initial(config, seed, roundId) -> RoundState`.
- `PhaseMachine.step(state, event, now) -> (RoundState, { Effect })` — two return
  values, the second always a real array (empty is `{}`, never `nil`).
- `RoundState` fields the assertions read: `phase` (`"Lobby"`, `"Assignment"`,
  `"Round"`, `"Resolution"`, `"Post"`), `phaseEnteredAt` (number),
  `players` (a **1-based array of string ids in seat order**, and seat order is
  join order), `seed`, `roundId`, `outcome`, and `config` — which the tests read
  back through the machine only, but which `step` must consult for
  `lobbySeconds`, `playersMin` and `playersMax`.
- Events constructed by the tests: `{ kind = "PlayerJoined", playerId }`,
  `{ kind = "PlayerLeft", playerId }`, `{ kind = "Tick" }`,
  `{ kind = "SeatsAssigned" }`, `{ kind = "RoundResolved", outcome }`.
- Effects read by the tests: `{ kind = "AssignSeats", seed, players }`.

**None of this changes.** The `## Contract` says no signature change, and that
is confirmed against the tree rather than repeated:
`grep -rn "PhaseMachine\|RoundConfig" src lune --include='*.luau'`, excluding the
two modules themselves, returns **0 lines**. Every caller is a test file under
`tests/server/`, and they call `initial` and `step` the same way before and after.

**What is NOT constrained, and stays GREEN's choice:** where the three new
guards live (inline in the `PlayerJoined` branch or in helpers), the order of the
clauses within a guard, how `PlayerLeft` locates the index, whether the count
gate is written as `#state.players >= state.config.playersMin` or via a local,
and whether a new `local function` is added. The only *placement* constraint is
the one `## Contract` pin 1 already fixes: the `Lobby -> Assignment` guard stays
inside the `Tick` branch, un-latched. A frozen `ROUND-003` test
(`AC-7: an unrecognised event is ignored in every phase, even when the phase's
duration is due`) drives `{ kind = "NotAnEventKind" }` at `now = 9` through a
four-player lobby with `lobbySeconds = 3`, and a guard evaluated at the top of
`step` fails it.

### Tests that passed on arrival

Three, each earned by a probe in `## Regressions` above, with the red pasted:

| Test | Probe |
|---|---|
| `AC-2: a PlayerJoined never rewrites phaseEnteredAt, whatever the now` | probe 1 — join restamps `phaseEnteredAt` |
| `AC-5: the same PlayerJoined applied twice seats that player once...` | probe 2 — duplicate guard dropped |
| `Contract pin 2: a PlayerLeft outside the Lobby is ignored...` | probe 3 — unconditional unseating branch |

The seven control tests also passed on arrival, by construction: their job is to
assert that a *check* refuses a *known-wrong machine*, and both the check and the
machine are test code. They are not green-on-arrival production assertions and
need no probe; each one is itself a `refuses(...)` that fails loudly if the check
it names becomes vacuous.

### The expected value of every negative control

**These are MEASURED, not predicted.** `src/server/round/PhaseMachine.luau`
exists, so `tests/server/lobby_gate_test.luau` loads and every assertion in the
suite ran — the usual RED caveat ("the file failed at import, so no control
executed") **does not apply here**. The numbers below were taken twice: once by
the control tests, which all pass, and once by driving the stubs directly outside
the test framework. Both agree.

Fixture: `lobbySeconds = 3`, `playersMin = 4`, `playersMax = 6`.

| Control | Scenario | Correct value | Control's measured value |
|---|---|---|---|
| `resetting` | 3 seated, held to `now = 9`, `p4` joins at `9` → `phaseEnteredAt` | `0` | **`9`** |
| `resetting` | then tick at `9.75` → phase | `Assignment` | **`Lobby`** |
| `resetting` | then tick at `12.0` → phase | `Assignment` | `Assignment` (it *does* start — the half a weaker test misses) |
| `holding` | the same three | `0` / `Assignment` at `9.75` (`phaseEnteredAt = 9.75`) / `Assignment` | identical |
| `evicting` | full lobby `[p1..p6]`, `p7` joins → list | `[p1 p2 p3 p4 p5 p6]`, length 6 | **`[p2 p3 p4 p5 p6 p7]`, length 6** — length identical, membership wrong |
| `reseating` | lobby of 4, `p5` joins twice → list | `[p1 p2 p3 p4 p5]`, `p5` once | **`[p1 p2 p3 p4 p5 p5]`, `p5` twice** |
| `swapping` | the AC-6 sequence → list | `[p2 p4 p5 p6 p8]` | **`[p6 p2 p5 p4 p8]`** — the right set, the wrong order |
| `mutatingRemover` | the AC-6 sequence → list | `[p2 p4 p5 p6 p8]` | `[p2 p4 p5 p6 p8]` — **identical**, which is the point |
| `mutatingRemover` | the caller's `players` after one leave | `[p1 p2 p3 p4]` (untouched) | **`[p1 p3 p4]`** — the input was edited under the caller |

**GREEN's job:** confirm the *correct* column against the shipped module. Every
one of those rows is a value the real `PhaseMachine` must produce, and the
control column is what it must not. If the shipped module produces a third thing,
say so in the story rather than adjusting a test.

### Verifications I could not run

None were deferred to me — `## Deferred verifications` is empty and correctly so.
One limitation is worth stating in writing rather than leaving to be discovered:

**AC-2's central assertion has not been observed failing against the real
machine.** The test fails on its AC-1 precondition — with no count gate, the
lobby of three is already in `Assignment` at `now = 9`, so the hold-versus-reset
assertion is never reached. It *has* been observed failing against
`LobbyGateStubs.resetting`, which is the implementation AC-2's criterion names,
and the measured values are in the table above. When GREEN lands the count gate,
the AC-2 assertion executes against the real machine for the first time;
**confirm it goes green for the right reason** (`phaseEnteredAt == 9.75` on the
started state, `0` on the post-join lobby) rather than merely that the test
passes.

### Mutation table — predictions for the orchestrator

For the **post-GREEN** machine. `bash scripts/mutate.sh` prints the whole suite,
so compare the FAIL list, not just the count. Expected clean run after GREEN:
`154 passed, 0 failed`.

| # | Mutation | Failures | Which |
|---|---|---|---|
| 1 | `PlayerJoined` sets `phaseEnteredAt = now` | **3** | `AC-2: a PlayerJoined never rewrites phaseEnteredAt, whatever the now`; `AC-2: reaching players_min starts the round on the next tick, without serving another lobbySeconds`; and **`AC-3: a departure below players_min holds the lobby, and restoring the count starts the round on the next tick`**, because the join that restores the count restamps too and the restored lobby is then made to serve another `lobbySeconds`. The story's `## Notes` predicts "AC-2 red, AC-1 green"; AC-3 is the third because this RED wrote the hold into it deliberately. AC-1, AC-4, AC-5, AC-6 and pin 2 stay green, and all 137 `ROUND-003` tests stay green — **observed**, under probe 1, where `seatedLobby()` joining at `now = 0` makes the restamp a no-op for them. |
| 2 | remove the `#players < playersMax` check | **1** | `AC-4: a join into a lobby holding players_max leaves exactly players_max seated and the surplus player unseated`, alone. AC-6's sequence never exceeds five seats, so it is unaffected. |
| 3 | duplicate-join guard always appends | **2** | `AC-5: the same PlayerJoined applied twice seats that player once, in a lobby at neither threshold`, plus `ROUND-003`'s frozen `AC-7: a duplicate PlayerJoined does not seat the same player twice`. **Observed in RED** under probe 2: `145 passed, 9 failed` against a baseline of `147 passed, 7 failed` — exactly those two, and no third. AC-6's sequence re-joins nobody, so it does not see this one. |

Two more worth running, because they are the defects this story's own controls
are aimed at and neither is in the original list:

| # | Mutation | Predicted |
|---|---|---|
| 4 | `PlayerLeft` removes by copying the last element over the hole | `AC-6: joins and leaves in any order leave the seated list a subsequence of the join order` goes red, alone. Nothing else sees it — that is the whole point of pin 4. |
| 5 | `PlayerLeft` removes with `table.remove(state.players, i)` on the input | `AC-3/AC-6: a PlayerLeft that unseats a player does not mutate the state it was given` goes red, alone; the list content stays correct everywhere. |

### Things GREEN should know

- **`PlayerLeft` unseats in `Lobby` only.** Probe 3 above showed that an
  *unconditional* removal branch turns the two order/purity tests green while
  turning the pin-2 test red. The removal logic is right; only the scope is
  wrong. Guard it on `state.phase == "Lobby"`.
- **A `PlayerLeft` for an unseated player must stay a no-op**, including in the
  Lobby — `ROUND-003`'s frozen `AC-7: an event naming a player who was never
  seated is ignored` drives `never-seated-p99` at a seated lobby. Returning a
  fresh deep-equal copy also passes (`eventIsIgnored` deep-compares rather than
  checking identity), but returning `state` is simpler.
- **Luau truncates an `assert` message at roughly 500 characters**, position
  prefix included. Measured on this suite: a first draft of the AC-6 message was
  cut off mid-trail at 503 characters of message plus a 74-character path prefix,
  and the evidence went with it. Both long messages in these files were
  rewritten to fit, with a comment saying why. If you add a diagnostic message
  anywhere in this repository, budget for it — a truncated failure looks like a
  crashed test.
- **The `unit` floor stays at 137 for now.** The real count is **154**; raising
  it is the Lead PO's move in GATES, per the story's `## Notes`.
- Nothing was amended in `## Contract`. Pin 1's correction was already in place
  when RED started and the tests were written to it: AC-2 and AC-3 both assert
  "on the next tick", and no test drives a non-`Tick` event expecting a duration
  to be evaluated.

---

## GREEN: control values confirmed

Every row of the handoff's control table was re-measured **against the shipped
`src/server/round/PhaseMachine.luau`**, not merely observed to be green: a
control test passing says a check refuses a stub, and a check can pass while
measuring something else. Two probes, both driven outside the test framework so
the numbers come from the machine rather than from an assertion's idea of it,
and both deleted afterwards (they lived under the gitignored `build/`).

Fixture in both: `lobbySeconds = 3`, `playersMin = 4`, `playersMax = 6` - the
same injected `CONFIG` the tests use.

| Control row | RED's "correct" value | RED's control value | GREEN measured, real machine | Agrees? |
|---|---|---|---|---|
| `resetting` - 3 seated, held to `now = 9`, `p4` joins at `9` -> `phaseEnteredAt` | `0` | `9` | **`0`** | yes |
| `resetting` - then tick at `9.75` -> phase | `Assignment` | `Lobby` | **`Assignment`**, `phaseEnteredAt = 9.75`, one `AssignSeats` | yes |
| `resetting` - then tick at `12.0` -> phase | `Assignment` | `Assignment` | **`Assignment`** | yes |
| `evicting` - full `[p1..p6]`, `p7` joins -> list | `[p1 p2 p3 p4 p5 p6]`, len 6 | `[p2 p3 p4 p5 p6 p7]`, len 6 | **`[p1 p2 p3 p4 p5 p6]`, len 6** | yes |
| `reseating` - lobby of 4, `p5` joins twice -> list | `[p1 p2 p3 p4 p5]`, `p5` once | `[p1 p2 p3 p4 p5 p5]` | **`[p1 p2 p3 p4 p5]`, `p5` occurs 1 time** | yes |
| `swapping` - the AC-6 sequence -> list | `[p2 p4 p5 p6 p8]` | `[p6 p2 p5 p4 p8]` | **`[p2 p4 p5 p6 p8]`** | yes |
| `mutatingRemover` - the AC-6 sequence -> list | `[p2 p4 p5 p6 p8]` | `[p2 p4 p5 p6 p8]` | **`[p2 p4 p5 p6 p8]`** | yes |
| `mutatingRemover` - the caller's `players` after one leave | `[p1 p2 p3 p4]` untouched | `[p1 p3 p4]` | **`[p1 p2 p3 p4]` untouched**, returned `[p1 p3 p4]`; neither the state table nor the `players` array is shared with the input | yes |

**No divergence anywhere.** The control (wrong) column was also re-measured
against `tests/helpers/LobbyGateStubs.luau` itself, unchanged, and reproduces
RED's numbers exactly - `resetting` `phaseEnteredAt = 9`, `Lobby` at `9.75`,
`Assignment` at `12`; `evicting` `[p2 p3 p4 p5 p6 p7]`; `reseating`
`[p1 p2 p3 p4 p5 p5]`; `swapping` `[p6 p2 p5 p4 p8]`; `mutatingRemover` leaving
the caller's list at `[p1 p3 p4]`. So RED measured the same objects GREEN did,
and its "correct" column was a description of the machine that shipped rather
than of a candidate one.

### AC-2, the one the PO ruling singles out: green for the RIGHT reason

`AC-2: reaching players_min starts the round on the next tick, without serving
another lobbySeconds` failed in RED on its **AC-1 precondition**, so its central
assertion had never executed against the real machine. Measured now, step by
step:

```
held at now = 9, 3 seated : phase = Lobby, phaseEnteredAt = 0   <- the precondition now holds
p4 joins at now = 9       : phaseEnteredAt = 0                  <- the join did NOT restamp
tick at now = 9.75        : phase = Assignment, phaseEnteredAt = 9.75, effects = [AssignSeats]
9 + lobbySeconds          : 12  <- where a restamping machine would have started
```

The lobby's `phaseEnteredAt` is still `0` when the last player arrives, and the
transition lands at `9.75`, the `now` the held time implies - not at `12`. A
machine that restamped on join *and* gated on the count would also have stopped
failing the precondition, and would have reached `Assignment` at `12`; this one
does not.

Confirmed a second way, because a measurement of a passing test is still only a
measurement: the story's mutation 1 was run through `scripts/mutate.sh` and
**observed failing**.

```
bash scripts/mutate.sh src/server/round/PhaseMachine.luau \
  's|\t\ttable.insert(seated.players, event.playerId)|\t\ttable.insert(seated.players, event.playerId)\n\t\tseated.phaseEnteredAt = now|' \
  -- lune run test
```

```
  FAIL  tests/server/lobby_gate_test.luau :: AC-2: a PlayerJoined never rewrites phaseEnteredAt, whatever the now
        ...\tests\server\lobby_gate_test:144: AC-2: seating p2 at now = 7 moved phaseEnteredAt from 0 to 7. The lobby timer HOLDS: the elapsed lobby time already served is never discarded by a join, or a lobby that gains and loses a player every thirty seconds never starts (M6)
  FAIL  tests/server/lobby_gate_test.luau :: AC-2: reaching players_min starts the round on the next tick, without serving another lobbySeconds
        ...\tests\helpers\LobbyGateContract:179: AC-2: the lobby was entered at 0, held past lobbySeconds (3) with 3 player(s), reached playersMin (4) at now = 9, and at the next tick (now = 9.75) the phase is Lobby. The 9 seconds already served are not discarded by a join: a machine still waiting here is one that restamped phaseEnteredAt and is serving another 3
  FAIL  tests/server/lobby_gate_test.luau :: AC-3: a departure below players_min holds the lobby, and restoring the count starts the round on the next tick
        ...\tests\helpers\LobbyGateContract:260: AC-3: restoring the count rewrote phaseEnteredAt from 0 to 15; neither a join nor a leave touches it
151 passed, 3 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/src_server_round_PhaseMachine.luau.20260916T011513Z.2755359.bak) ===
```

(Paths elided to `...` for width, as elsewhere in this story.)

**Exactly the three failures the handoff's mutation table predicts, and by
name** - RED's prediction of 3 rather than `## Notes`' prediction of 1 is
confirmed against the post-GREEN machine. All 137 `ROUND-003` tests stayed
green. The file was restored and the restore verified; `git diff -- src`
afterwards shows only this story's change, and no `.bak` remains under
`.claude/state/mutations/`.

### What GREEN changed, and why each line is where it is

All three changes are in the body of `PhaseMachine.step` / `onTick`: no new
module, no signature change, and `RoundConfig.luau` untouched. `playersMin` and
`playersMax` are read off `state.config`, never from `Tuning` and never as a
literal.

| Change | Where | Why there |
|---|---|---|
| `or #state.players >= state.config.playersMax` added to the `PlayerJoined` refusal | the existing guard in the `PlayerJoined` branch | AC-4. The refusal keeps the existing shape - `return state, {}`, nothing raised, nothing mutated - so it is indistinguishable from any other ignored event (pin 3) |
| a new `PlayerLeft` branch, `Lobby` only, `table.remove` on the **copy** at the departing player's seat | between `PlayerJoined` and `SeatsAssigned` | AC-3, AC-6 and pin 2. Guarded on `state.phase == "Lobby"`, so `Assignment`, `Round`, `Resolution` and `Post` keep ignoring it (`ROUND-005` owns the mid-round rule); `table.remove` closes the hole rather than swapping the last element in, so the list stays a subsequence of the join order; `copyOf` keeps the input untouched; a leave naming an unseated player returns `state` itself, so `ROUND-003`'s never-seated test is still a no-op |
| `and #state.players >= state.config.playersMin` added to the `Lobby -> Assignment` guard | **inside `onTick`**, the existing `Tick` branch | Pin 1. Not hoisted to the top of `step`, which would transition on `{ kind = "NotAnEventKind" }` and break the frozen `ROUND-003` test `AC-7: an unrecognised event is ignored in every phase, even when the phase's duration is due`. Nothing is latched: both halves are re-evaluated on every tick, so a tick that found the time due while the lobby was short leaves no trace |

A helper `seatOf(state, playerId): number?` was added and `isSeated` rewritten
as `seatOf(...) ~= nil`, so the join guard and the leave share one definition of
"which seat".

`phaseEnteredAt` is untouched on both the join path and the leave path. That
absence is the hold, and it is what the mutation above turns into three
failures.

The module header's `OUT OF SCOPE` paragraph was updated in the same change: it
still named this story's lobby gate as unbuilt and still said `PlayerLeft` is
"ignored by every phase here", which stopped being true.

### Runs

```
lune run test                  -> 154 passed, 0 failed (exit 0)
stylua --check src tests lune  -> exit 0
selene src tests lune          -> 0 errors, 0 warnings, 0 parse errors

bash scripts/gates.sh --fast
PASS         format (0s, observed 30)
PASS         lint (1s, observed 30, floor 1)
PASS         typecheck (3s, observed 7)
PASS         unit (26s, observed 154, floor 137)
UNCONFIGURED coverage
PASS         build (1s, observed 17308)
changes: 1 changed source path(s), all exercised by a required gate
All required gates passed (5 ran, 1 unconfigured, 0 known).
```

`observed 154` for `unit` against a floor of **137**, which this story does not
raise - that is the Lead PO's move in GATES, per `## Notes`. A `--fast` run is
not recorded and is not evidence; the full `gates.sh` has not been run in this
phase and `## Gate results` is untouched.

Nothing in `## Contract` or the handoff turned out to be wrong, and nothing was
escalated: no criterion here is over-specified, and no test needed changing.

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-16T01:34:35Z
    commit: b3d838a (working tree had uncommitted changes)
    tree:   bc20bb7191b1129cfbce29a11644b098fc816b8e
    result: pass (5 ran, 3 unconfigured, 0 known)

    PASS         format (1s, observed 30)
    PASS         lint (1s, observed 30, floor 1)
    PASS         typecheck (3s, observed 7)
    PASS         unit (26s, observed 154, floor 154)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (1s, observed 17308)
    UNCONFIGURED mutation

