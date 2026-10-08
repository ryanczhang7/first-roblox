---
id: THEME-001
title: Design tokens exist in source and meet the accessibility floor
slug: design-tokens-exist-in-source-and-meet-t
epic: EPIC-03
type: feature
status: in-progress
phase: RED
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
- **AC-4** (PT-T3) — Given every system colour token, when its chroma
  `(max(r, g, b) − min(r, g, b)) / 255` is computed, then it is at most 0.15.
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

**Pinned at PLANNED → RED (Lead PO, 2026-10-08).** The blocks below sharpen
the sketch above. RED may amend a block in place, with a one-line reason, and
GREEN builds what the amended block says. No AC text changed.

- **C-1. `Theme.size` holds two dimensions.** `Theme.size: { [string]: { x: number, y: number } }`.
  The flat-number sketch cannot hold `96 × 112`. One entry per `tokens.md` §5
  first table row, named by its token. A single value is a square (`x = y`).
  Where the Value cell gives two numbers (`size.reticle` "12 (idle), 20
  (target)"), the first is the entry. The secondary values (the next-cue 32,
  the reticle's 20, the segment gap 4) are out of scope; a component story adds
  them, under a name the Lead Designer records.
- **C-2. "Target" means an interactive control's size.** AC-3's targets are
  exactly `size.target.min`, `size.button.action` and `size.tile.preset`, the
  §5 rows that size something a player presses (A-1). Both dimensions × 0.9
  must be ≥ 44. `size.icon.hud` (32 → 28.8) is not a target, and asserting it
  as one would be a wrong test.
- **C-3. `Theme.type` holds the base size.** `Theme.type: { [string]: number }`
  maps each §3 token to its base size (`type.caption` → 18). Font, line height
  and weight are out of scope until a view needs them.
- **C-4. Icon keys are read out of `tokens.md`, verbatim and in table order.**
  `Theme.icons.tags` holds the §2.1 keys, `patterns` the §2.3 keys and
  `system` the §2.4 keys. `presets` maps each `Presets.ALL[i].key` (`"ready"`,
  `"on_my_way"`, …) to its §2.5 icon key (`"preset.ready"`). `Presets` lives at
  `src/ReplicatedStorage/Shared/channel/Presets.luau`; it carries no icon on
  purpose, because `Theme` owns the icon.
- **C-5. Audio rows that name two cues are two cues.** In §8,
  `sfx.ui.press / sfx.ui.denied` and `sfx.outcome.won / sfx.outcome.lost` are
  four `Theme.audio` keys. Each takes the matching half of its row's visual
  (`press state` / `wait state`; `the outcome banner` for both outcomes).
- **C-6. Compositing (AC-2).** The composite is per channel in gamma-encoded
  sRGB: `c = (1 − t)·scrim + t·#FFFFFF` with `t` = the scrim's transparency,
  unrounded. Contrast is WCAG 2: relative luminance from linearised sRGB, and
  `(L1 + 0.05) / (L2 + 0.05)`. The §1.4 pairings are the four text/stroke rows
  plus the violet row plus **all six** `color.player.*` hues at floor 3.0
  (amended in RED, 2026-10-08: the table has four text/stroke rows, not five;
  the violet row resolves by hex to `color.player.4` at the same floor, so the
  distinct set is 10 (token, floor) pairs). The "player hues (worst:
  vermillion)" row is read as every hue. The table's printed ratios (13.6,
  4.39, …) are informative and rounded; a test reads the **floors**, never
  those ratios. Measured by the Lead PO at PLANNED with an independent awk
  script: composite `#2B2E32`; worst text 7.47 (muted, floor 4.5); worst floor-3.0 item
  4.17 (vermillion); AC-2's control `#6A727E` 2.82, so it fails.
- **C-7. Machado 2009 is applied in linear RGB (AC-6).** Linearise sRGB,
  multiply by the severity-1.0 matrix (Machado, Oliveira & Fernandes, IEEE
  TVCG 15(6), 2009, Table 2), clamp each channel to [0, 1], then XYZ (D65,
  sRGB primaries) → CIE Lab (Xn 0.95047, Yn 1, Zn 1.08883) → CIE76. This is
  **not a free choice**. The Lead PO reproduced `tokens.md` §1.2's published
  minima at PLANNED with an independent awk script under this reading. Linear
  gives seats 1–6: normal 34.93, protan 20.71, deutan 13.46, tritan 11.18;
  seats 1–4 min 28.64; hue vs white/grey 16.82, matching 34.9 / 20.7 / 13.5 /
  11.2 / 28.6 / 16.8. The gamma-encoded reading does **not**: deutan 9.74 < 10
  and hue-vs-grey 7.43 < 15, so a module applying the matrix to gamma-encoded
  values fails PT-T7 against the shipped tokens. RED's "one known value" check
  (contract above) can use those six published minima as its worked example.
- **C-8. Layer and requires.** Client tests require production code by
  relative path (`../../src/client/Theme`), as server tests do. Client source
  requires `@game/ReplicatedStorage/Shared/…` only.
- **C-9. No changed signatures.** All three modules are new. Nothing existing
  changes, so there are no callers to list.

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

Lock coverage: SUPPRESSED by `scripts/classify.sh` (tooling), `src/ReplicatedStorage/Shared/channel/Presets.luau` (source), `src/client/Theme.luau` (source) (+3 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
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
- RED - `test-developer` - `claude-fable-5-1` (explicit `model: fable`; agent reported no override; resumed once for the AC-4 amendment). 2026-10-08.

## Test plan

All unit level, under Lune, in a new `tests/client/` directory. The idiom is
the repo's: a **spec reader** (`tests/helpers/TokenSpec.luau`) that parses
`tokens.md` off disk through `GatedFs`; a **contract** helper
(`tests/helpers/ThemeContract.luau`) holding every check as a function of an
implementation `{ Theme, ColourMath, ScreenScale }` and a context `{ spec,
mechanics, session, presets }`; **stubs** (`tests/helpers/ThemeStubs.luau`)
with a reference derived from the document and one-defect variants; and a
**test-side colour reference** (`tests/helpers/ColourRef.luau`) so the
arithmetic controls can be measured in RED.

| File | Level | What it pins | Runs in RED? |
|---|---|---|---|
| `tests/client/theme_test.luau` | unit, real modules | AC-1 .. AC-7, C-1, C-3, C-4, C-5, one case per check, through the shipped `ColourMath` | red at `impl()` (modules absent) |
| `tests/client/colour_math_test.luau` | unit, real `ColourMath` | C-6, C-7: known values, the six published minima, agreement with `ColourRef`, the three arithmetic controls through the shipped module; D-1's subjects | red at `CM()` (module absent) |
| `tests/client/client_requires_test.luau` | unit, tree scan | C-8: `src/client/**` requires only its layer or `@game/ReplicatedStorage/Shared/` | red (the three modules are not in the scanned set) |
| `tests/client/theme_controls_test.luau` | unit, no production code | every `ThemeContract` check and every `TokenSpec` vacuity step observed firing; the `[measured]` numbers the handoff quotes | 31 of 31 green (the baseline was red on the AC-4 finding until the amendment; see handoff §0) |

**Oracle partition honoured.** AC-1, AC-5's key sets, C-1, C-3, C-4, C-5 read
every value out of `tokens.md`; no hex or key list is restated in any test
(the only hexes in `tests/` are the controls' injected values `#DDEBFE`,
`#6A727E`, `#FF00FF`, PT-T7's two reference colours `#FFFFFF` / `#8A93A0`,
the worst background `#FFFFFF`, and pure colours in `colour_math_test`'s
known-value cases). AC-2, AC-3, AC-4, AC-6, AC-7 use the thresholds the
criteria state (listed with their source in `ThemeContract`'s header) over the
shipped module's arithmetic. The counts the parser's vacuity pins
(`TokenSpec.EXPECTED`) are counts, not values; two of them come from
`Tuning.session.players_max` and `#Presets.ALL`.

**Edges covered.** Empty parser result (every spec-driven check refuses to
compare); a transparency dropped and a transparency raised; a target one
pixel short on both axes; the type floor one pixel short; `uiScale` without
its clamp; a breakpoint that passes all four AC-3 sizes and fails only the
formula's edges (429/479/480); a tag duplicating a glyph; too few tags; a
preset icon missing and two swapped; detents offset by one position; detents
accepting 7; a cue missing from a two-cue row; a blank visual.

## Handoff: RED -> GREEN

**Written by the Test Developer, 2026-10-08. Dispatched with `model: fable`
per the plan; resolved to Fable 5.1 (`claude-fable-5-1`).**

### 0. AC-4 escalation - RESOLVED by `## Amendments` (chroma), 2026-10-08

**Resolution.** AC-4 now reads chroma `(max(r, g, b) − min(r, g, b)) / 255 ≤
0.15` (approved by the user; `tokens.md` §1.1 and `accessibility.md` PT-T3
amended to match). The check (`ThemeContract.systemColoursAreAchromatic`),
the shipped-module export (`ColourMath.chroma`, replacing `saturation`, which
nothing else needed and which is no longer pinned), `ColourRef`, the
`strokeTinted` control (vermillion `#E8671C`: chroma **0.800**, was HSV 0.879)
and the baseline case were corrected in RED. Measured chroma of every §1.1
token under the reference: scrim 0.031, raised 0.055, selected 0.075,
text.primary 0, text.muted 0.078, text.disabled 0.086, stroke.control 0.086,
stroke.focus 0, signal.on 0, signal.off 0.075, **signal.lens 0.133 (max)**,
world.housing 0.071, world.pattern 0.067, world.neutralTrim 0.078 - all ≤
0.15, matching the Lead PO's independent measurement in `## Notes`. The
baseline control now passes (`reference fails 0 of 15 checks`). The
`tokens.md` edit added two lines after §1.1, which changed no parsed count
(vacuity still reads 21/14/6/10/6/6/16/10/5/10/14); the controls that named
a document line now read it from the parsed row rather than hard-coding it.
One further control change surfaced by the fix: a §1.1 token *missing* from
`Theme.color` (`colourMissing`) fires AC-4 as well as AC-1, because the
check refuses a token it cannot measure rather than skipping it - pinned.

The original finding is kept below for the record.

AC-4 said every `tokens.md` §1.1 system token has **HSV saturation at most
0.15**, and `tokens.md` §1.1 claimed the same ("No system role has a
saturation above 0.15 (HSV)"). Measured in RED with `S = (max − min) / max`
over the document's own values, **six of the fourteen did not**:

    PT-T3: color.surface.scrim #0E1116 has HSV saturation 0.364, above 0.15
    PT-T3: color.surface.raised #1B2029 has HSV saturation 0.341, above 0.15
    PT-T3: color.surface.selected #2A313D has HSV saturation 0.311, above 0.15
    PT-T3: color.signal.off #2A313D has HSV saturation 0.311, above 0.15
    PT-T3: color.world.housing #3A414C has HSV saturation 0.237, above 0.15
    PT-T3: color.world.neutralTrim #5C6470 has HSV saturation 0.179, above 0.15

(`#0E1116` is r 14, g 17, b 22: (22 − 14) / 22 = 0.364. The arithmetic is
not in doubt; HSL saturation gives 0.222 for the same colour, also above
0.15. Only a *chroma* measure - `max − min` = 0.031 - describes these dark
blue-greys as near-achromatic, which is plainly the design intent.)

The test pinned AC-4 exactly as then written and was red against the
reference; option (a) - amend the metric to chroma - was taken.

### 1. Command

    lune run test                       # whole suite, ~5 min
    lune run build/one_test.luau -- tests/client/theme_test tests/client/colour_math_test tests/client/client_requires_test tests/client/theme_controls_test

`build/one_test.luau` is the gitignored single-file runner. If it is
missing, recreate it with this body (it mirrors `lune/test.luau`'s loop
over the paths given after `--`):

    local process = require("@lune/process")
    local passed, failed = 0, 0
    for _, path in process.args do
        if path == "--" then continue end
        local ok, suite = pcall(require, "../" .. path)
        if not ok then
            print(`  LOAD FAIL  {path}\n             {tostring(suite)}`)
            failed += 1
        else
            local names = {}
            for name in suite do table.insert(names, name) end
            table.sort(names)
            for _, name in names do
                local ran, err = pcall(suite[name])
                if ran then passed += 1; print(`  pass  {path} :: {name}`)
                else failed += 1; print(`  FAIL  {path} :: {name}\n        {tostring(err)}`) end
            end
        end
    end
    print(`{passed} passed, {failed} failed`)
    process.exit(if failed > 0 or passed == 0 then 1 else 0)

The gates: `bash scripts/gates.sh --fast`.

### 2. The red, verbatim, and why it is the right one

`theme_test.luau`, every one of its 15 cases:

    FAIL  tests/client/theme_test :: AC-1: Theme.color holds every backticked color.* row of tokens.md with its hex and its stated transparency, and no colour no row names - after the reader's vacuity steps
          D:\first-roblox\tests\client\theme_test:52: src/client/Theme.luau did not load: error requiring module "../../src/client/Theme": could not resolve child component "Theme"

`colour_math_test.luau`, every one of its 12 cases:

    FAIL  tests/client/colour_math_test :: D-1: contrast(white, black) is 21, contrast(white, white) is 1, and the ratio is the same in either order
          D:\first-roblox\tests\client\colour_math_test:58: src/client/models/ColourMath.luau did not load: error requiring module "../../src/client/models/ColourMath": could not resolve child component "models"

`client_requires_test.luau`, its scan case:

    FAIL  tests/client/client_requires_test :: C-8: every module under src/client/ requires only its own layer or @game/ReplicatedStorage/Shared/…, and the three Contract modules are among those scanned
          D:\first-roblox\tests\client\client_requires_test:81: 3 Contract module(s) are not in the scanned set (classify.sh --list source src/client returned 1 file(s)):
      src/client/Theme.luau
      src/client/models/ScreenScale.luau
      src/client/models/ColourMath.luau

`theme_controls_test.luau`: `31 passed, 0 failed` (before the AC-4 amendment:
`30 passed, 1 failed`, the baseline red on the finding in section 0).

Why right: the three modules are the thing this story builds and none
exists, so each criterion fails at the require, per criterion, with no stub
standing in. Because of that, **not one assertion past `impl()` / `CM()` in
`theme_test` or `colour_math_test` has executed**. What *has* executed, in
RED, is every check in `ThemeContract` and every vacuity step in `TokenSpec`,
through `theme_controls_test.luau` - the "fires exactly" set of every
single-defect control is printed there as `[measured]` and reproduced in
section 6.

### 3. Files touched

| File | Role |
|---|---|
| `tests/helpers/TokenSpec.luau` | new - reads tokens.md §1.1/1.2 (colours), §1.4 (pairings → floors), §2.1/2.3/2.4 (keys), §2.5 (preset word → icon key), §3, §5, §8; vacuity pins counts |
| `tests/helpers/ColourRef.luau` | new - TEST-SIDE reference arithmetic (C-6, C-7), verified against the six published minima; not the module under test, never required from `src/` |
| `tests/helpers/ThemeContract.luau` | new - 15 checks over `{ Theme, ColourMath, ScreenScale }` |
| `tests/helpers/ThemeStubs.luau` | new - reference derived from the document; 21 one-defect variants |
| `tests/client/theme_test.luau` | new - the real modules against the contract |
| `tests/client/colour_math_test.luau` | new - the real `ColourMath` against C-6/C-7 and the reference |
| `tests/client/client_requires_test.luau` | new - C-8 |
| `tests/client/theme_controls_test.luau` | new - the controls, run in RED |
| `.claude/tests/project-counters.test.sh` | baselines → post-GREEN prediction 228/228/40, narrow 40/40/9 (PO decision 4) |
| `docs/backlog/stories/THEME-001.md` | `## Test plan`, this section |

Test → AC map (`theme_test.luau`, one case per contract check):

| Case | Asserts | Covers |
|---|---|---|
| AC-1 | every `color.*` row exists with its hex (case-insensitive, `#RRGGBB`) and stated transparency; no extra key | AC-1 |
| AC-2 (PT-A1, PT-A4) | each §1.4 (token, Floor) ≥ floor through `ColourMath.contrast` over `composite(scrim, t, #FFFFFF)`; scrim `t ≤ 0.12`; a scrim with no numeric transparency is refused | AC-2 |
| AC-3 (PT-A2, PT-A3) | `size.target.min`, `size.button.action`, `size.tile.preset`: both axes × 0.9 ≥ 44; every §3 type × 0.9 ≥ 16 | AC-3 |
| AC-3 (PT-L1) | `uiScale`/`breakpoint` at 568×262, 667×339, 1024×700, 1920×1000 → 0.9 compact, 0.9 compact, 1.3 regular, 1.3 regular; plus edges 351→0.9, 390→1.0, 429→1.1, 479→479/390 compact, 480→480/390 regular, 507→1.3, and (300, 800)→0.9 compact | AC-3 |
| AC-4 (PT-T3) | every §1.1 token `ColourMath.chroma ≤ 0.15` (amended metric; see §0) | AC-4 |
| AC-5 (PT-T4) | tags, patterns, system, preset values pairwise disjoint | AC-5 |
| AC-5 (PT-T5) | `#tags ≥ MechanicsTuning.instance.tag_alphabet_size` (4; the doc has 6) | AC-5 |
| AC-5 presets | `icons.presets[Presets.ALL[i].key]` = §2.5 key of the row whose word is `ALL[i].word`; no extra keys | AC-5 |
| AC-5 (PT-T6) | `detents(n)`, n = 2..6: n entries, `angle = (i−1)·360/n`, `pips = i`; `detents(7)` and `detents(8)` raise | AC-5 |
| AC-6 (PT-T7) | pairwise ΔE ≥ 30 normal, ≥ 10 per simulation; seats 1–4 ≥ 25 in all four modes; each hue ≥ 15 from `#FFFFFF` and `#8A93A0` in all four | AC-6 |
| AC-7 (PT-A5) | every `audio` entry has a non-blank `visual` | AC-7 |
| C-1 / C-3 / C-4 / C-5 | `size`, `type`, `icons.{tags,patterns,system}`, `audio` equal the document row for row, no extras | Contract |

### 4. Export shape the tests already pin (fact, not suggestion)

    src/client/Theme.luau                                    -- required as "../../src/client/Theme"
      Theme.color:   { [string]: { hex: string, transparency: number? } }
                     keys are the token names verbatim ("color.surface.scrim", ...);
                     hex is "#RRGGBB" (compared upper-cased); transparency equals the
                     row's stated value where one is stated (0.12, 0.12, 0)
      Theme.size:    { [string]: { x: number, y: number } }     -- C-1, every §5 size.* row
      Theme.type:    { [string]: number }                       -- C-3, every §3 row's base size
      Theme.icons:   { tags: { string }, patterns: { string }, system: { string },
                       presets: { [string]: string } }          -- C-4; presets keyed by Presets.ALL[i].key
      Theme.audio:   { [string]: { visual: string } }           -- C-5, 14 cues
      Theme.detents(n: number) -> { { angle: number, pips: number } }
                     entry i: angle (i-1)*360/n, degrees clockwise from the top; pips i.
                     Raises (error) for n = 7 and n = 8. n < 2 is NOT constrained.

    src/client/models/ScreenScale.luau                       -- "../../src/client/models/ScreenScale"
      ScreenScale.uiScale(width: number, height: number) -> number
                     clamp(min(w, h) / 390, 0.9, 1.3), compared to 1e-9
      ScreenScale.breakpoint(width: number, height: number) -> "compact" | "regular"
                     "compact" iff min(w, h) < 480

    src/client/models/ColourMath.luau                        -- "../../src/client/models/ColourMath"
      type RGB = { r: number, g: number, b: number }           -- gamma-encoded sRGB, each in [0, 1]
      ColourMath.fromHex(hex: string) -> RGB                   -- "#RRGGBB"; lower case accepted
      ColourMath.toHex(c: RGB) -> string                       -- "#RRGGBB" upper case, rounded to 8 bits
      ColourMath.luminance(c: RGB) -> number                   -- WCAG 2 relative luminance (0.2126/0.7152/0.0722, 0.03928 knee)
      ColourMath.contrast(a: RGB, b: RGB) -> number            -- (L1+0.05)/(L2+0.05), L1 the lighter; >= 1 either order
      ColourMath.composite(fg: RGB, transparency: number, bg: RGB) -> RGB   -- (1-t)*fg + t*bg per channel, unrounded (C-6)
      ColourMath.chroma(c: RGB) -> number                      -- max(r,g,b) - min(r,g,b) over [0,1] channels = (max-min)/255 over 8-bit (AC-4 as amended). No `saturation` export is pinned.
      ColourMath.toLab(c: RGB) -> { L: number, a: number, b: number }
                     linearise -> XYZ (sRGB D65: 0.4124564 0.3575761 0.1804375 / 0.2126729 0.7151522 0.0721750 /
                     0.0193339 0.1191920 0.9503041) -> Lab with Xn 0.95047, Yn 1, Zn 1.08883
      ColourMath.deltaE(a: RGB, b: RGB) -> number              -- CIE76 in that Lab
      ColourMath.simulate(c: RGB, mode: "protan" | "deutan" | "tritan") -> RGB
                     linearise, multiply by the Machado 2009 severity-1.0 matrix (C-7), clamp each channel
                     to [0, 1], re-encode to gamma sRGB. The matrices the reference uses, which the
                     agreement test holds the module to at 1e-6:
                       protan { 0.152286, 1.052583, -0.204868 / 0.114503, 0.786281, 0.099216 / -0.003882, -0.048116, 1.051998 }
                       deutan { 0.367322, 0.860646, -0.227968 / 0.280085, 0.672501, 0.047413 / -0.011820, 0.042940, 0.968881 }
                       tritan { 1.255528, -0.076749, -0.178779 / -0.078411, 0.930809, 0.147602 / 0.004733, 0.691367, 0.303900 }
                     Cite the source in a comment (Contract).

`tests/helpers/ColourRef.luau` is a complete worked implementation of this
shape, written to C-6/C-7 and verified against the published minima. GREEN
may read it; GREEN may not require it from `src/`, and `ColourMath` should
be written from the Contract, not copied, so the agreement test compares two
derivations rather than one with itself.

Shared modules the tests already require and the client modules must not
contradict: `src/ReplicatedStorage/Shared/MechanicsTuning.luau`
(`.instance.tag_alphabet_size`), `.../Shared/Tuning.luau`
(`.session.players_max`), `.../Shared/channel/Presets.luau` (`.ALL[i].key`,
`.ALL[i].word`). Client source requires these as
`@game/ReplicatedStorage/Shared/…` only (C-8; `client_requires_test`).

**Not constrained** (implementer's choice): freezing; a transparency field
on a colour whose row states none (nil or 0 both pass); `Theme.detents` for
n ≤ 1; any extra member on the three modules beyond the names above (AC-1,
C-1, C-3, C-5 forbid extra *keys inside* `color`/`size`/`type`/`audio`, not
extra module members); how `Theme` is organised internally (one table
literal, built from sub-tables, whatever); whether `ColourMath` exposes
linearise/encode helpers; file layout under `src/client/` beyond the three
paths.

### 5. Tests green on arrival, and what earns them

- `client_requires_test` "C-8 control" - an in-memory negative control; it
  *is* the earning for the scan case, which is red until the modules exist.
- `theme_controls_test.luau`, 30 cases - controls by design, measured in RED;
  each pins the exact fire-set of a one-defect stub. They are the
  instrument, not the subject. Nothing else is green.

### 6. Negative controls: expected values, measured in RED

Measured through `ColourRef` (test-side reference), **not the shipped
module**, which does not exist. `colour_math_test.luau` holds the shipped
module to the starred rows; GREEN's job is to see that file go green and to
quote its `[measured, shipped]` lines here.

| Control | Check / threshold | Expected | Measured in RED (reference) | Fires exactly |
|---|---|---|---|---|
| `lensChanged` `color.signal.lens` → `#DDEBFE` | AC-1 equality | refused, naming token and both hexes | "Theme says #DDEBFE, tokens.md line 69 says #DDEBFF" | AC-1 |
| `playerSevenAdded` | AC-1 no extra | refused, naming `color.player.7` | "no tokens.md row names it" | AC-1 |
| `colourMissing` (world.pattern) | AC-1; AC-4 refuses an unmeasurable token | refused twice | "missing from Theme.color"; "no entry with a hex string" | AC-1, AC-4 |
| `transparencyDropped` (scrim nil) | AC-1; AC-2 refuses to composite | refused twice | AC-2: "transparency nil, expected a number" | AC-1, AC-2 |
| `transparencyRaised` (scrim 0.2) | PT-A4 ≤ 0.12 | 0.2 refused; every pairing still clears | "transparency is 0.2, above the ceiling 0.12", 1 violation | AC-1, AC-2 |
| parser matching no rows | vacuity | "matched nothing", nothing compared | 10 spec-driven checks fire | AC-1..AC-4, AC-5(presets), AC-6, C-1, C-3, C-4, C-5 |
| **`mutedDarkened`** `#6A727E` \* | AC-2 floor 4.5 | 2.82 (PO: 2.82) | **2.82** | AC-1, AC-2 |
| shipped `color.text.muted` \* | AC-2 floor 4.5 | 7.47 (PO: 7.47) | **7.47** | - |
| worst floor-3.0 item (vermillion) \* | AC-2 floor 3.0 | 4.17 (PO: 4.17) | **4.17** | - |
| worst composite \* | C-6 | `#2B2E32` | **#2B2E32** | - |
| `targetShrunk` 48×48 | PT-A2 ≥ 44 | 43.20 on both axes | 43.20 | AC-3, C-1 |
| `captionShrunk` 17 | PT-A3 ≥ 16 | 15.30 | 15.30 | AC-3, C-3 |
| `scaleUnclamped` | PT-L1 | 0.67, 0.87, 1.79, 2.56 and 0.77 at (300, 800); clamp edges agree | 5 violations | AC-3 |
| `breakpointAt400` | PT-L1 | passes all four AC-3 sizes; caught at 429, 479, 480 | 4 violations | AC-3 |
| **`strokeTinted`** (stroke.control := player.3) \* | PT-T3 chroma ≤ 0.15 | 0.800 | **0.800** (0.879 under the superseded HSV reading) | AC-1, AC-4 |
| `tagIsAGlyph` | PT-T4 | "glyph.key is in both tags and system" | as expected | AC-5, C-4 |
| `tagsTooFew` (3) | PT-T5 ≥ 4 | 3 < 4 | as expected | AC-5, C-4 |
| `presetIconMissing` / `presetIconSwapped` | AC-5 | nil / "preset.wait" for ready | as expected | AC-5 |
| `detentsFromTheRight` | PT-T6 | 20 angle violations (2+3+4+5+6) | 20 | AC-5 |
| `detentsAcceptSeven` | PT-T6 | 7 and 8 returned instead of raising | 2 | AC-5 |
| **`playerTwoIsFive`** \* | PT-T7 | ΔE 0.00 seats 2/5 in all four modes; seats 2/3 under protan 20.71 and deutan 14.06 < 25 | **0.00 ×4, 20.71, 14.06**; 6 violations | AC-1, AC-6 |
| shipped hues, PT-T7 minima \* | ≥ 30 / 10 / 25 / 15 | 34.9 / 20.7 / 13.5 / 11.2 / 28.6 / 16.8 (tokens.md §1.2); PO 34.93 / 20.71 / 13.46 / 11.18 / 28.64 / 16.82 | **34.93 / 20.71 / 13.46 / 11.18 / 28.64 / 16.82** | - |
| `visualBlank` (sfx.ping) | PT-A5 | refused | as expected | AC-7, C-5 |
| `cueMissing` (sfx.ui.denied) | C-5 | refused, naming line 400 | as expected | C-5 |
| `contrastConstant21` (D-1's shape) | AC-2 depends on `contrast` | `mutedDarkened` stops firing AC-2 | fires AC-1 only | AC-1 |
| document fixtures: no colour row; one row dropped from three tables; a row doubled; §1.4 hex disagreeing; §1.4 unknown token | `TokenSpec.vacuity` | each named | as expected | - |
| AC-4 on the shipped tokens (§0) | PT-T3 chroma ≤ 0.15 | all 14 ≤ 0.133 (signal.lens the max) | measured 0.031 .. 0.133; **the reference fires nothing** (under the superseded HSV reading it fired AC-4 at 0.364 .. 0.179) | - |

Reference verification (C-7's "one known value before trusting the
matrices"): under the linear-RGB reading the reference reproduces all six
published minima to two decimals; pure red simulates to `#A39000` (deutan)
and `#6D5F00` (protan); a grey is unchanged in every mode. Those are pinned
in `colour_math_test.luau` for the shipped module.

### 7. D-1 (GATES) - declined in RED, prediction

RED cannot run D-1: there is no `ColourMath.contrast` to mutate. Predicted
under `bash scripts/mutate.sh src/client/models/ColourMath.luau '<contrast → return 21>' -- lune run build/one_test.luau -- tests/client/theme_test tests/client/colour_math_test`:

- `theme_test` AC-2 stays **green** (every pairing reads 21 ≥ floor) - which is
  the "control passes wrongly" D-1 looks for, seen through the shipped Theme.
- `colour_math_test` goes **red on exactly three cases**: "D-1: contrast(white,
  black) is 21, contrast(white, white) is 1 …" (white/white reads 21),
  "D-1, control (AC-2) through the shipped module: #6A727E … reads 2.82"
  (reads 21), and "agreement: … contrast … agree with the test-side reference"
  (every pair differs). All other cases unchanged. Restored: all green.
- `theme_controls_test` is unchanged (it uses the reference arithmetic).

### 7b. `bash scripts/gates.sh --fast` on the RED tree, after the AC-4 amendment (2026-10-08, local)

    PASS         format (1s, observed 225)
    PASS         lint (1s, observed 225, floor 1)
    PASS         typecheck (3s, observed 37)
    FAIL         unit (450s, exit 1) -> .claude/state/gate-logs/unit.log
    UNCONFIGURED coverage
    PASS         build (2s, observed 138085)
    FAIL         harness (31s, exit 1) -> .claude/state/gate-logs/harness.log

Unit: `1493 passed, 28 failed`; all 28 are `tests/client/` (15 `theme_test`,
12 `colour_math_test`, 1 `client_requires_test`; `theme_controls_test` is
fully green - before the amendment the run read 1492 / 29 with its baseline red). Harness: `project-counters: 29 passed, 12
failed`, every failure the predicted gap (`228 / 225`, `229 / 226`, `40 /
37`, `41 / 38`) plus the stray-file precondition. Format, lint, typecheck and
build are green on the new test files, so the tests are admissible to the
gates that will judge them. Timings are local; no test here owns a timeout.

### 8. Things GREEN should know

- **§1.4 pairing count.** C-6 said "the five text/stroke rows plus all six
  player hues"; amended in place in RED to "four text/stroke rows plus the violet row". The table has four text/stroke rows, the "player hues" row
  (expanded to six) and a "violet `#B58CFF`" row that resolves by hex to
  `color.player.4` at the same floor and dedupes. The parser pins **10**
  distinct (token, floor) pairs; nothing is lost and no AC text is affected.
- **`tag_alphabet_size` is 4**, not 6: `MechanicsTuning.instance.tag_alphabet_size = 4`
  (derived, = `machines_per_class_max`). The document has six tags; AC-5's
  "at least" holds with room. `accessibility.md` PT-T5 words it as
  `ceil(actuator_count / players_min)` = 4 as well.
- **Counters.** `.claude/tests/project-counters.test.sh` is set to the
  post-GREEN prediction. Expected red in RED: `expected count: 228 / actual
  count: 225` (format, lint), `229 / 226` (untracked cases), `40 / 37`
  (typecheck, narrow src), and the stray-file precondition until the RED
  commit. GREEN confirms; a fourth source file is a counter failure.
- **`discovery | client`** (project.conf) is the orchestrator's at GATES, once
  `lune run test -- --list` is seen listing `tests/client/`. It does, today,
  with the four files.
- `ColourRef` keeps its Machado matrices in `ColourRef.MACHADO`; the shipped
  module's must agree to 1e-6 ΔE over the shipped tokens, which it will if
  copied from the same published table.

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

## Amendments

**AC-4, 2026-10-08, in RED. Approved by the user (product owner) in the
`/complete-story` session.**

- **Said:** "Given every system colour token, when its HSV saturation is
  computed, then it is at most 0.15."
- **Says now:** "Given every system colour token, when its chroma
  `(max(r, g, b) − min(r, g, b)) / 255` is computed, then it is at most 0.15."
  The control is unchanged.
- **Why:** RED measured six of the fourteen §1.1 tokens above 0.15 HSV
  saturation (scrim 0.364). The Lead PO reproduced this independently; the
  output is in `## Notes`. HSV saturation is a ratio to the brightest channel,
  so near-black blue-greys score high while carrying almost no colour. What
  §0 protects is that no system colour can be mistaken for a player hue, and
  absolute chroma measures that: all fourteen pass (worst `signal.lens`
  0.133), and the control (`stroke.control` set to a player hue) still fails.
  No colour value changed. The alternative, desaturating six tokens, would
  have moved the §1.4 composite and every contrast ratio.
- **Also amended to match:** `tokens.md` §1.1's sentence and `accessibility.md`
  PT-T3. RED corrects the AC-4 check and its control; no other test is
  affected.

## Notes

**PO decisions at PLANNED → RED (2026-10-08, Lead PO, `/complete-story`).**

1. **Required gate:** `unit`. The story adds `covers | unit | src/client/**`
   **now, at PLANNED**, not at GATES as the contract first said. Otherwise a
   GREEN `--fast` run judges new client source by lint, typecheck and build
   alone. The `discovery | client` line stays at GATES, added once
   `lune run test -- --list` is observed listing `tests/client/`.
2. **Contract C-1 to C-7** fix shapes and readings the sketch left open. C-6
   and C-7 rest on the independent computation recorded in them. In
   particular, the AC-6 thresholds are satisfiable by the shipped tokens only
   under the linear-RGB reading, so this is a reading to pin, not an open
   ambiguity.
3. **Epic done-when** clause 5 is this story's own and is covered by AC-1 to
   AC-7. No gap.
4. **Counter baselines.** GREEN adds three files under `src/client/`, so RED
   sets `.claude/tests/project-counters.test.sh` to the post-GREEN prediction
   and commits it in a `phase: RED` commit (check-boundaries 3j).


**AC-4 escalation from RED, reproduced by the Lead PO (2026-10-08).** RED
reported that the shipped tokens fail AC-4 as written. I checked this with a
separate bash/awk computation that reuses none of RED's code: hexes read from
`tokens.md` §1.1, HSV S = (max − min) / max per token.

    color.surface.scrim     HSV-S 0.364  chroma 0.031  <-- over 0.15
    color.surface.raised    HSV-S 0.341  chroma 0.055  <-- over 0.15
    color.surface.selected  HSV-S 0.311  chroma 0.075  <-- over 0.15
    color.signal.off        HSV-S 0.311  chroma 0.075  <-- over 0.15
    color.world.housing     HSV-S 0.237  chroma 0.071  <-- over 0.15
    color.world.neutralTrim HSV-S 0.179  chroma 0.078  <-- over 0.15
    (the other eight are ≤ 0.138; max chroma over all 14 is signal.lens 0.133)

The claim holds. AC-4, PT-T3 and `tokens.md` §1.1's sentence all name HSV
saturation, and the near-black blue-greys fail it while carrying almost no
colour. The PLANNED check missed it. Put to the user before GREEN; see
`## Amendments`.
