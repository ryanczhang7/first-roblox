---
id: THEME-001
title: Design tokens exist in source and meet the accessibility floor
slug: design-tokens-exist-in-source-and-meet-t
epic: EPIC-03
type: feature
status: todo
phase: PLANNED
branch: story/THEME-001-design-tokens-exist-in-source-and-meet-t
depends_on: [TUNE-001, CHAN-002]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-03`. The Lead Designer's first pass (`docs/wiki/design/`) fixes the
colour roles, the player palette, the four symbol alphabets, the type and size
scales and the layout scale. It also fixes an accessibility floor whose rules
are written to be checked by pure tests. Those are the PT-* checks in
`docs/wiki/design/accessibility.md` §3.

`architecture.md` §9.9: `src/client/Theme.luau` implements the tokens **by their
names in the design documents**, the way `Tuning.luau` implements `tuning.md`.
Every client story after this reads its tokens from here. This story builds the
module, a drift guard against `tokens.md`, and the PT checks that concern tokens
alone. The PT checks that concern a component model belong to that component's
story.

It is the first story to put source in `src/client/`. So it is where the `unit`
gate learns to read the directory: `covers | unit | src/client/**`, plus a
`discovery | client` line once `tests/client/` exists. Without those, a client
module read only by optional gates fails the run (`quality-gates`).

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given `tokens.md` parsed off disk, when every table row whose first
  cell is a backticked `color.*` token is compared with `Theme.color`, then each
  token exists with the hex value its row states. Where the row states a
  transparency, that exists too. `Theme.color` has no colour that no row names.
  *Controls:* `color.signal.lens` changed to `#DDEBFE` must fail, naming it. An
  extra `color.player.7` must fail. A parser that matches no rows must fail
  rather than compare nothing.
- **AC-2** (PT-A1, PT-A4) — Given `Theme`, when every foreground/background
  pairing in `tokens.md` §1.4 is composited over white at the scrim's
  transparency, then each meets its stated WCAG 2 contrast floor, and the
  scrim's transparency is at most 0.12.
  *Control:* `color.text.muted` darkened to `#6A727E` must fail.
- **AC-3** (PT-A2, PT-A3, PT-L1) — Given the size and type tokens and
  `ScreenScale.uiScale(width, height)`, when each is multiplied by the scale
  floor 0.9, then every target is at least 44 and every type size at least 16.
  `uiScale` and `breakpoint` return the values `layout.md` states at 568 × 262,
  667 × 339, 1024 × 700 and 1920 × 1000.
- **AC-4** (PT-T3) — Given every system colour token, when its HSV saturation is
  computed, then it is at most 0.15.
  *Control:* `color.stroke.control` set to a player hue must fail.
- **AC-5** (PT-T4, PT-T5, PT-T6) — Given the four icon-key sets (tags, class
  patterns, system glyphs, preset icons), when they are compared:
  - they are pairwise disjoint;
  - the tag set has at least `MechanicsTuning.instance.tag_alphabet_size` keys;
  - there is exactly one preset icon for each `Presets.ALL` key;
  - `Theme.detents(n)` returns `360 / n` spaced angles from the top with pips
    `1..n` for `n` in 2..6, and raises for 7.
- **AC-6** (PT-T7) — Given the six player hues, when pairwise CIE76 ΔE is
  computed in normal vision and under Machado 2009 protan, deutan and tritan
  simulation at severity 1.0, then the thresholds `accessibility.md` PT-T7
  states hold.
  *Control:* replacing `color.player.2` with `color.player.5`'s value must fail.
- **AC-7** (PT-A5) — Given `Theme.audio`, when each cue is read, then it has a
  non-empty visual-equivalent key.

## Contract

**Modules**, all pure, under `src/client/`:

    src/client/Theme.luau
        Theme.color:   { [string]: { hex: string, transparency: number? } }   -- keys are the token names, verbatim
        Theme.size:    { [string]: number }       -- tokens.md §5, base pixels before UIScale
        Theme.type:    { [string]: number }       -- tokens.md §3
        Theme.icons:   { tags: {string}, patterns: {string}, system: {string}, presets: { [string]: string } }
        Theme.audio:   { [string]: { visual: string } }   -- tokens.md §8
        Theme.detents(n: number) -> { { angle: number, pips: number } }
    src/client/models/ScreenScale.luau
        ScreenScale.uiScale(width: number, height: number) -> number
        ScreenScale.breakpoint(width: number, height: number) -> "compact" | "regular"
    src/client/models/ColourMath.luau        -- WCAG luminance, contrast, HSV, Lab, CIE76, Machado 2009
        (exported for tests and for later models; pure arithmetic)

- `src/client/models/` is `src/client/` code with no Instance in it. Every
  client model lives there.
- The Machado 2009 matrices are published constants. Cite the source in a
  comment. A wrong matrix is caught by AC-6's control only if the matrix is
  right, so RED checks one known value (for example, a pure red under deutan
  simulation) against a published worked example before trusting the rest.
- **Client imports** are `@game/ReplicatedStorage/Shared/…` only (`MechanicsTuning`, `Presets`; spelling per `SLICE-008`). The
  net layer (`@game/ReplicatedStorage/Net/…`) is not needed until `SLICE-002`, and this story does not need
  it.

**The spec reader** is `tests/helpers/TokenSpec.luau`, which reads
`docs/wiki/design/tokens.md` through `GatedFs`. The Lead PO added
`covers | unit | docs/wiki/design/tokens.md` at planning (2026-09-30), so the
path is in the gate hash. `bash scripts/classify.sh --gated` lists it.

**`project.conf`, by the orchestrator at GATES:**

    covers    | unit   | src/client/**
    discovery | client | . | lune run test -- --list | grep -E 'tests/client/' > /dev/null

Observe `lune run test -- --list` listing `tests/client/` before
adding the discovery line (`quality-gates`: a discovery claim is checked by
running the runner).

**Oracle partition.**
- AC-1 and AC-5 are **settled** by `tokens.md`. Read them out, and never
  restate a hex value in a test.
- AC-2 to AC-4, AC-6 and AC-7 are **settled** thresholds from
  `accessibility.md` over **mechanical** arithmetic. Each has a control that
  breaks one token.

## Deferred verifications

**D-1. The contrast arithmetic is not vacuous.** Use `scripts/mutate.sh` to
make `ColourMath.contrast` return a constant 21. AC-2's control **must** then
pass (wrongly), which shows the control depends on the function. The real
suite, restored, must reject the control again. RED cannot run this. Owner:
GATES.

## Out of scope

- Any component model or view. Each belongs to its story.
- Icon images: M3 uses glyph placeholders (operator question Q-O1).
- The tone of the dark (M4).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write THEME-001` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `scripts/classify.sh` (tooling), `src/client/Theme.luau` (source), `src/client/models/ColourMath.luau` (source) (+2 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

Partition as in `## Contract`.

**Dispatch note.** To run RED on the planned `fable` row, the orchestrator must pass
`model: fable` explicitly in the dispatch. ROUND-006 omitted it, and the agent
definition's `model: opus` won instead. If the contract is still to be amended
from an upstream story or spike (as noted above), amend it and re-run
`bash scripts/plan.sh write` first.

**Resolved:**

- PLANNED - `lead-po` - `claude-opus-5-5` (Opus 5.5, from the session's own model
  identification; the /plan-product dispatch reported no override). 2026-09-30.

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

