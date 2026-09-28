---
id: HARNESS-016
title: Every contract helper raises through the shared raiser
slug: every-contract-helper-raises-through-the
epic: 
type: chore
status: todo
phase: PLANNED
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
