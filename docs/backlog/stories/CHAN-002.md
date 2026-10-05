---
id: CHAN-002
title: The preset table obeys the countable preset-guideline rules
slug: the-preset-table-obeys-the-countable-pre
epic: EPIC-06
type: feature
status: in-progress
phase: RED
branch: story/CHAN-002-the-preset-table-obeys-the-countable-pre
depends_on: [TUNE-001]      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-06`. The preset wheel is a **compliance surface** (brief §0d #19):
Roblox's preset-system guidelines limit a universe to 12 presets, forbid presets
that carry hidden or evolving meaning, and forbid terminal punctuation.
`mechanics.md` §4.3 turns those into rules C1–C9 and says which are checked by a
headless test: **C1** (count), **C2** (no fact-bearing word, by denylist),
**C6** (no terminal punctuation) and **C8** (no question, greeting or polarity
pair). This story builds the preset table as data and pins those four.

The table is shared: the server validates sends against it and the client draws
the wheel from it.

**Which required gate would fail if this story's artifact broke:** `unit`.

## Acceptance criteria

- **AC-1** — Given `mechanics.md` §4.2's preset table, when it is parsed off
  disk and compared to `Presets.ALL`, then the two agree row for row: the same
  words in the same order, and the same legal phases for each. A preset added,
  removed, reworded or re-phased on either side fails, naming the preset.
  *Control:* a module with one word changed (`"Go"` → `"Go now"`) must fail,
  naming it; and a parser that matches no rows must fail rather than compare
  nothing.
- **AC-2** — Given the module and `MechanicsTuning`, when the counts are
  compared, then `#Presets.ALL == preset_count` and
  `preset_count + ping_kinds <= presets_plus_pings_max` (C1).
- **AC-3** — Given every preset word, when it is split into lower-cased words,
  then none is in the fact denylist (C2, C8): colour, shape, number and digit,
  ordinal and sequence, direction, polarity (yes/no) and greeting words.
  *Control:* the check must fail for a hand-built table containing `"Red"`,
  `"Two"`, `"First"`, `"Left"`, `"Yes"` and `"Hello"`, naming each.
- **AC-4** — Given every preset word, when its last character is read, then it
  is not `.`, `!` or `?` (C6).
  *Control:* `"Help!"` must fail.
- **AC-5** — Given every preset's phase list, when it is read, then it is
  non-empty and each entry is one of the five phase names `Remotes.Phase`
  declares.

## Contract

**Module.** `src/shared/channel/Presets.luau`, frozen data.

    export type Preset = {
        id: number,          -- 1..preset_count, the wheel order; also the wire value
        key: string,         -- stable ascii id: "ready", "wait", "go", "help", "on_my_way",
                             -- "follow_me", "got_it", "thanks", "nice_one", "well_played"
        word: string,        -- exactly the mechanics.md §4.2 word
        phases: { string },  -- e.g. { "Round", "Lobby" }
    }
    Presets.ALL: { Preset }             -- frozen, in mechanics.md §4.2 order
    Presets.byId(id: number) -> Preset? -- nil for anything not an id in ALL

- **No icon field.** Which icon a key shows is presentation, in the client's
  `Theme` (`docs/wiki/design/`), keyed by `key`.
- `phases` is `{ string }` rather than a phase union: `src/shared/` cannot
  import `src/net/` or `src/server/` (`architecture.md` §1), and a third
  textual copy of the union is what `phase_union_guard_test` exists to
  prevent. AC-5 checks membership instead.

**The spec reader.** A test helper, `tests/helpers/PresetSpec.luau`, reads
`docs/wiki/game/mechanics.md` through `GatedFs` (in the gate hash since the
Lead PO added its `covers` line at planning) and extracts the §4.2 table: the
rows under the heading `### 4.2 The preset wheel` whose first cell is a
backticked word. The phases cell is split on commas. Three vacuity steps, as
`RateLimitSpec` does: exactly ten rows, each with a word and at least one phase,
before any comparison.

**The denylist** lives in the test, and it is an invented oracle: start from the
categories C2 and C8 name and list concrete words for each. It must not contain
any of the ten shipped words' tokens (`ready`, `wait`, `go`, `help`, `on`, `my`,
`way`, `follow`, `me`, `got`, `it`, `thanks`, `nice`, `one`, `well`, `played`)
— **except that `one` is a number word**. `Nice one` therefore needs a
decision, and it is taken here: the check is on **whole preset words that name a
fact**, and `"one"` is excluded from the number list with a comment citing
`mechanics.md` §4.2, where the operator chose `Nice one` (T12). Listing `one` and
then special-casing the preset would make the check fail open for every future
preset.

**Pinned at PLANNED → RED (lead-po, 2026-10-05).** RED may amend any block
here in place with a dated reason; GREEN builds what the amended block says.

- **P-1. AC-5's five names are read, not copied.** `Remotes.Phase` is a type and
  has no runtime value, so the test obtains the set by applying
  `tests/helpers/PhaseUnion.luau` to `src/net/Remotes.luau` (the same textual
  extraction `phase_union_guard_test` uses), asserts that set is non-empty and
  equals `PhaseUnion.KNOWN`, and checks membership against the **extracted** set.
  A fourth hand-written list of phase names in the test is what P-1 forbids.
- **P-2. The spec reader's parsing.** A row is a `|`-delimited line under
  `### 4.2 The preset wheel`, before the next `###`, whose first cell (trimmed)
  is one backtick-quoted string; the word is the text between the backticks,
  kept exactly (case and inner spaces). The **third** cell is the phases, split
  on `,`, each trimmed. Order is file order. The header and `|---|` rows have no
  backticked first cell and are skipped. Vacuity first: exactly ten rows, each
  with a non-empty word and at least one phase.
- **P-3. `id` and `key`.** `id` is the 1-based position in `ALL` (the test
  asserts `ALL[i].id == i`). `key` is exactly the list above, in order. Neither
  is in `mechanics.md`; both are pinned here and asserted against this list.
- **P-4. `byId`.** Returns the same table as `ALL[id]` for `id` in
  `1..#ALL`, and `nil` for `0`, `#ALL + 1`, `1.5`, `-1` and a non-number.
- **P-5. Frozen.** `ALL`, each `Preset` and each `phases` list are frozen
  (`table.isfrozen`), so a client cannot rewrite the wheel the server checks.
- **P-6. Counter baselines.** GREEN adds exactly one source file
  (`src/shared/channel/Presets.luau`, in `src/shared`). RED sets the
  `.claude/tests/project-counters.test.sh` baselines to the **post-GREEN**
  values (its own test files + 1 source file; typecheck +1; narrow typecheck
  `src/shared` +1) and commits them in a `phase: RED` commit, as the harness
  rules require.

**Callers of changed signatures.** None: `Presets` is a new module.
`rg -n "Presets\b|PresetSpec" src tests` returned nothing at `5e6d97b`. RED
re-runs it and says so in the handoff.

**Oracle partition.** AC-1 and AC-2 are **settled**: the words and counts are
the operator's (T12) and `tuning.md`'s; read them out. AC-3 is **oracle-free**:
the denylist is invented, and its control is the hand-built bad table. AC-4 and
AC-5 are **mechanical**.

## Deferred verifications

**D-1. AC-1 reads the real module.** Use `scripts/mutate.sh` on
`src/shared/channel/Presets.luau` to change the word `"Go"` to `"Go now"`. AC-1
**must** fail, naming `Go now` (or `Go`). RED cannot run this: the module does
not exist. Owner: GATES.

**D-2. AC-1 reads the real phases.** Use `scripts/mutate.sh` to drop `"Post"`
from `Well played`'s phases (leaving it `{}` or another phase, whichever the
expression produces). AC-1 **must** fail naming `Well played`. Owner: GATES.

**D-3. AC-4 reads the real words.** Use `scripts/mutate.sh` to make `"Help"`
`"Help!"`. AC-4 **must** fail naming it. Owner: GATES.

## Out of scope

- The remote, rate limiting and broadcast (`CHAN-003`).
- Filtering (`CHAN-004`).
- The wheel's look (`HUD-004`).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write CHAN-002` from `.claude/harness/models.conf`.
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

Lock coverage: SUPPRESSED by `src/net/Remotes.luau` (source), `src/shared/channel/Presets.luau` (source), `tests/helpers/PhaseUnion.luau` (test) (+1 more), scanned from the Contract text — the phase lock freezes them, so RED follows the plain plan.
<!-- plan.sh:generated:end -->

Partition as in `## Contract`. RED reads the words from `mechanics.md`, never
from this story.

**Dispatch note.** To run RED on the planned `fable` row, the orchestrator must pass
`model: fable` explicitly in the dispatch. ROUND-006 omitted it, and the agent
definition's `model: opus` won instead. If the contract is still to be amended
from an upstream story or spike (as noted above), amend it and re-run
`bash scripts/plan.sh write` first.

**Resolved:**

- PLANNED - `lead-po` - `claude-opus-5-5` (Opus 5.5, from the session's own model
  identification; the /plan-product dispatch reported no override). 2026-09-30.
- RED - `test-developer` - `claude-fable-5-1` (Fable 5.1), from an **explicit
  `model: fable` in the dispatch**, per the plan; the agent reported the same id.
  2026-10-05.

## Test plan

All unit level, under `lune run test`; the module is pure data and the
contract lives in one file, so nothing cheaper or dearer applies.

**Shape (house pattern).** The checks are written once in
`tests/helpers/PresetContract.luau` over a module handed in as a parameter
plus a `Context` (the §4.2 rows off disk, the Phase set out of
`Remotes.luau`, the tuning). `tests/shared/presets_test.luau` applies them to
the real `src/shared/channel/Presets.luau` through a per-test `pcall` require,
so each criterion fails separately. `tests/shared/presets_controls_test.luau`
applies the same checks to `tests/helpers/PresetStubs.luau`'s reference and
to tables with exactly one defect each, so every check is OBSERVED firing in
RED while the real-module suite cannot get past the missing require.

**Oracle partition, honoured.**

| AC | Oracle | Where the number comes from | Negative control |
|---|---|---|---|
| AC-1 | settled | `PresetSpec.rows(PresetSpec.read())` — mechanics.md §4.2 through `GatedFs`, three vacuity steps first | `wordChanged` (Go → Go now); `rowRemoved`, `rowAdded`, `rowsSwapped`, `phaseDropped`, `phaseChanged`; a context with zero rows fails on vacuity and compares nothing |
| AC-2 | settled | `MechanicsTuning.channel.{preset_count, ping_kinds, presets_plus_pings_max}` | substituted `ping_kinds = 3` fires the C1 clause only; `preset_count = 11` fires the count clause only |
| AC-3 | invented | `PresetContract.DENYLIST`, nine categories, `one` excluded with the T12 citation | the hand-built table Red, Two, First, Left, Yes, Hello names all six with categories; a multi-word table names only the offending token; the denylist is checked against every shipped token read from §4.2 |
| AC-4 | mechanical | last character ∈ {`.`, `!`, `?`} | `Help!`; `Wait.`, `Ready?`, and `Go, now` not named |
| AC-5 | mechanical | P-1: `PhaseUnion.read` over `src/net/Remotes.luau`, asserted equal to `PhaseUnion.KNOWN` as a set; membership against the extracted set | `Intermission`; an empty phase list; an empty Phase set refused before any membership |
| P-3 | mechanical | `id == i`, `PresetContract.KEYS` by position, fields exactly `{id, key, phases, word}` | ids 0..9; `go → go_now`; an `icon` field |
| P-4 | mechanical | `byId(i)` is `rawequal` to `ALL[i]`; nil for 0, #ALL+1, 1.5, -1, `"1"` | a flooring/coercing `byId`; a `byId` that returns a copy |
| P-5 | mechanical | `table.isfrozen` on ALL, each preset, each phases | each of the three left unfrozen |

**Spec reader (P-2)** is driven over fixture documents: no heading → zero rows
→ "matched nothing"; nine rows → the count and the words; an empty phases
cell and empty backticks → named rows; header/separator/out-of-section rows
skipped; the section also ends at a `##` heading; case, inner spaces, comma
splitting and line numbers kept.

**Counters (P-6).** `.claude/tests/project-counters.test.sh` baselines set to
the predicted post-GREEN values 182/182/30, narrow 30/30/9 (five test files +
one source file under `src/shared/`).

## Handoff: RED -> GREEN

**Written by the Test Developer, 2026-10-05. Resolved model: `claude-fable-5-1`
(Fable 5.1) — the planned `fable` row; the dispatch reported no override.**

### Command

    lune run test            # from the repo root; write it to a file, never through `| head`

The runner has no filter; the whole suite runs (~8 min here, 469 s under the
`unit` gate). The two new suites are `tests/shared/presets_test.luau` (the
real module) and `tests/shared/presets_controls_test.luau` (the controls).

### Failure output, verbatim, and why it is the right failure

    1164 passed, 8 failed

    FAIL  tests/shared/presets_test.luau :: AC-1: Presets.ALL agrees row for row with mechanics.md §4.2 read off disk - same words, same order, same phases - after the reader's three vacuity steps (ten rows, each with a word and at least one phase)
          D:\first-roblox\tests\shared\presets_test:48: src/shared/channel/Presets.luau did not load: error requiring module "../../src/shared/channel/Presets": could not resolve child component "channel"
    FAIL  tests/shared/presets_test.luau :: AC-2: ...   (same message)
    FAIL  tests/shared/presets_test.luau :: AC-3: ...   (same message)
    FAIL  tests/shared/presets_test.luau :: AC-4: ...   (same message)
    FAIL  tests/shared/presets_test.luau :: AC-5: ...   (same message)
    FAIL  tests/shared/presets_test.luau :: P-3: ...    (same message)
    FAIL  tests/shared/presets_test.luau :: P-4: ...    (same message)
    FAIL  tests/shared/presets_test.luau :: P-5: ...    (same message)

All eight failures are the one the story requires first: the module
`src/shared/channel/Presets.luau` does not exist (the directory `channel`
does not exist under `src/shared/`). Each criterion fails separately at the
`pcall`-guarded require, not as one LOAD FAIL. Nothing else regressed: the
run before this story's files was 1160 passed (the first run with four
wrong control needles showed 1160/12; after correcting the needles,
1164/8). The controls file passes 31/31.

`bash scripts/gates.sh --fast` (same tree):

    PASS         format (2s, observed 181)
    PASS         lint (3s, observed 181, floor 1)
    PASS         typecheck (5s, observed 29)
    FAIL         unit (469s, exit 1)        -> 1164 passed, 8 failed, the eight above
    UNCONFIGURED coverage
    PASS         build (2s, observed 115815)
    FAIL         harness (40s, exit 1)      -> project-counters: 27 passed, 13 failed

The 13 harness failures are exactly the predicted RED red (P-6): the
precondition "the working tree carries no stray .luau files" (the five
untracked test files; clears at the RED commit) and the twelve counter
assertions reading `expected 182 / actual 181` (format, lint, and their
ignored-file cases), `30 / 29` (typecheck, narrow format, narrow lint, and
typecheck's ignored-file case), `9 / 8` (narrow typecheck over src/shared),
`183 / 182` and `31 / 30` (the untracked-file cases). All twelve clear when
GREEN adds the one file under `src/shared/`. No other harness assertion
fails. No lint, format or typecheck finding on any new file.

### Files touched

| File | Purpose |
|---|---|
| `tests/helpers/PresetSpec.luau` | new — reads mechanics.md §4.2 through `GatedFs`; `rows`, `vacuity`, `read`, `describe`, `EXPECTED_ROWS = 10` |
| `tests/helpers/PresetContract.luau` | new — the eight checks over a module parameter + `Context`; `DENYLIST`, `KEYS`, `FIELDS`, `tokens`, `deniedAs`, `phaseSet`, `CHECKS`, `failures` |
| `tests/helpers/PresetStubs.luau` | new — the reference table (fixture copy of §4.2), `build`, `with(defect)`, `factTable` |
| `tests/shared/presets_test.luau` | new — the real module, one test per AC-1..AC-5, P-3, P-4, P-5 |
| `tests/shared/presets_controls_test.luau` | new — 31 controls; see the table below |
| `.claude/tests/project-counters.test.sh` | baselines 176/176/29, 29/29/8 → 182/182/30, 30/30/9 (predicted post-GREEN), with the LAST SET entry |
| `docs/backlog/stories/CHAN-002.md` | `## Test plan`, this section |

Test → AC map (`presets_test.luau`): AC-1 `tableMatchesTheSpec`; AC-2
`countsAgreeWithTheTuning`; AC-3 `noWordNamesAFact`; AC-4
`noWordEndsInTerminalPunctuation`; AC-5 `phasesAreNonEmptyAndKnown`; P-3
`idsAreIndicesAndKeysArePinned`; P-4 `byIdReturnsTheEntryOrNil`; P-5
`everyTableIsFrozen`.

### The export shape the tests already pin (fact, not suggestion)

`require("../../src/shared/channel/Presets")` from `tests/shared/` — so the
file is **`src/shared/channel/Presets.luau`** and returns a table `Presets`
with:

- `Presets.ALL : { Preset }` — a list, `#ALL == 10`, in mechanics.md §4.2
  order. `table.isfrozen(ALL)` must be true.
- `Presets.byId : (id: any) -> Preset?` — `rawequal(byId(i), ALL[i])` for
  `i` in `1..10` (the same table, not a copy); returns `nil` (does not raise)
  for `0`, `11`, `1.5`, `-1` and the string `"1"`. `ALL[id]` indexing satisfies
  all of that; a `tonumber`/`math.floor` is a failure.
- Each `Preset` has **exactly** the fields `id`, `key`, `word`, `phases` —
  P-3 compares the sorted key set to `{ "id", "key", "phases", "word" }`, so an
  `icon` or any extra field fails. `table.isfrozen(preset)` must be true.
  - `id == i`, its 1-based position in `ALL`.
  - `key` is exactly, by position: `ready`, `wait`, `go`, `help`, `on_my_way`,
    `follow_me`, `got_it`, `thanks`, `nice_one`, `well_played`.
  - `word` is exactly the §4.2 word, case and spaces as written: `Ready`,
    `Wait`, `Go`, `Help`, `On my way`, `Follow me`, `Got it`, `Thanks`,
    `Nice one`, `Well played`. (Read them from the document, not from here.)
  - `phases` is a `{ string }` compared with `Deep.equal` to the document's
    third cell split on commas **in document order**: `Ready` →
    `{ "Round", "Lobby" }` (Round first), `Thanks` and `Nice one` →
    `{ "Round", "Post" }`, `Well played` → `{ "Post" }`, every other →
    `{ "Round" }`. `table.isfrozen(phases)` must be true.

**Not constrained** (the implementer's choice): whether the module table
itself is frozen; the `export type Preset` declaration and whether `phases`
is a named type; how `byId` is implemented beyond its results; any extra
module member (only `ALL` and `byId` are read); comments, layout, and whether
the ten entries are literals or built by a loop and then frozen. The module
must not import `src/net` or `src/server` (`architecture.md` §1) — nothing
in it needs to; the phases are strings.

### Tests that passed on arrival, and what earns them

Everything in `presets_controls_test.luau` is green on arrival **by
design** — it imports no unmerged code — and each test earns its place by
observing a check refuse a defective input (table below). Two tests in it
are regression-shaped guards of invariants earlier stories established:
the P-1 test (the Phase set read from `Remotes.luau` equals `KNOWN`;
`phase_union_guard_test` already pins this) earns itself with two in-test
negative controls (a side with 0 declarations, a side with a sixth phase,
both refused by `phaseSet`); the settled-numbers test reads `preset_count`,
`ping_kinds`, `presets_plus_pings_max` out of `MechanicsTuning`, which
`mechanics_tuning_spec_test` already pins to `tuning.md` — it is here so a
moved number is named next to the suite it would silently re-tune.

### Negative controls — measured, not claimed

Unlike the usual RED, these numbers are **measured**: the controls file does
not import the missing module, so every control below actually ran, twice
(`lune run test` and the `unit` gate), with the same result. "Fires" is the
exact, sorted set of `PresetContract` checks that raised; each control pins
that set exactly, and each message was asserted to open with its `AC-n:` /
`P-n:` header. GREEN's job on this table is to confirm the **real module**
passes all eight (the `baseline` row), and GATES's is D-1..D-3.

| Control (stub) | What changed vs the reference | Expected fires | Measured fires | Measured detail |
|---|---|---|---|---|
| `reference` | nothing | none | **0 of 8** | the fixture copy agrees with the document read off disk |
| `{}` (empty module) | no `ALL` | all 8 at `need()` | 8 of 8 | each message: `Presets.ALL is nil, expected a list of presets` |
| `wordChanged` (D-1's shape) | `Go` → `Go now` | AC-1 | AC-1 | `row 3: the module's word is "Go now", mechanics.md §4.2 says "Go"` |
| `rowRemoved` | `Help` removed | AC-1, AC-2, P-3 | AC-1, AC-2, P-3 | `ALL has 9 preset(s), §4.2 has 10; missing from the module: "Help"`; `#Presets.ALL is 9, preset_count is 10` |
| `rowAdded` | `Okay` appended | AC-1, AC-2, P-3 | AC-1, AC-2, P-3 | `not in the document: "Okay"`; `#Presets.ALL is 11, the Contract pins 10 keys` |
| `rowsSwapped` | `Wait` ↔ `Go`, keys kept in Contract order | AC-1 (revised, see below) | AC-1 | rows 2 and 3 named both ways |
| `phaseDropped` (D-2's shape) | `Well played` → `{}` | AC-1, AC-5 | AC-1, AC-5 | `row 10 "Well played": the module's phases are {  }, §4.2 says { 1 = "Post" }`; `the phase list is empty` |
| `phaseChanged` | `Wait` → `{ "Lobby" }` | AC-1 | AC-1 | AC-5 satisfied; only the document catches it |
| `emptyRows` (context with 0 rows) | parser matched nothing | AC-1 | AC-1 | `the extraction matched nothing ... (nothing was compared)`; no `Presets.ALL has` clause |
| `pingKinds3` (tuning `ping_kinds = 3`) | 10 + 3 = 13 > 12 | AC-2 | AC-2 | C1 clause only; count clause absent |
| `presetCount11` (tuning `preset_count = 11`) | 10 ≠ 11; 11 + 1 = 12 allowed | AC-2 | AC-2 | count clause only; no `C1:` |
| `factTable` | Red, Two, First, Left, Yes, Hello | AC-1, AC-2, AC-3, P-3 | AC-1, AC-2, AC-3, P-3 | AC-3: **6 violation(s)**, `red` colour, `two` number, `first` ordinal, `left` direction, `yes` polarity, `hello` greeting |
| `multiWord` | `Go left now`, `Make a Circle`, `Press 2`, `You next` | AC-1, AC-2, AC-3, P-3 | same | AC-3: **4 violation(s)**: `left`, `circle`, `2`, `next`; `"go"` not named |
| `terminalPunctuation` (D-3's shape) | `Help` → `Help!` | AC-1, AC-4 | AC-1, AC-4 | `row 4 "Help!": ends in "!", terminal punctuation (C6)` |
| `punctuation` | `Wait.`, `Ready?`, `Go, now` | AC-1, AC-2, AC-4, P-3 | same | AC-4: **2 violation(s)**; `Go, now` not named |
| `unknownPhase` | `Wait` → `{ "Intermission" }` | AC-1, AC-5 | AC-1, AC-5 | `the phase "Intermission" is not one Remotes.Phase declares (Assignment, Lobby, Post, Resolution, Round)` |
| `emptyPhaseSet` (context with `{}`) | no phases read | AC-5 | AC-5 | `the Phase set read out of src/net/Remotes.luau is empty` |
| `idOffByOne` | ids 0..9 | P-3 | P-3 | **10 violation(s)**; `row 1 "Ready": id is 0, expected 1` |
| `keyChanged` | `go` → `go_now` | P-3 | P-3 | **1 violation(s)**; `the Contract pins "go"` |
| `iconField` | `icon` on every preset | P-3 | P-3 | **10**; fields `{ icon, id, key, phases, word }` vs `{ id, key, phases, word }` |
| `byIdLenient` | `floor(tonumber(id))` | P-4 | P-4 | **2 violation(s)**: `byId(1.5)`, `byId("1")`; `byId(0)` correctly nil |
| `byIdReturnsCopy` | `table.clone(ALL[id])` | P-4 | P-4 | **10**; `expected the same table as ALL[1] ("Ready")` |
| `unfrozenAll` / `unfrozenPreset` / `unfrozenPhases` | one level unfrozen each | P-5 | P-5 each | `Presets.ALL is not frozen`; **10** `the preset table is not frozen`; `the phases list is not frozen` |

Settled numbers measured: §4.2 reads as **10** rows (= `EXPECTED_ROWS` =
`preset_count`); `ping_kinds` **1**; `presets_plus_pings_max` **12**; Phase
set read from `Remotes.luau` = `{ Assignment, Lobby, Post, Resolution,
Round }`; the ten words split into **16** tokens
(`ready wait go help on my way follow me got it thanks nice one well played`),
none denied; `deniedAs("one") == nil`, `deniedAs("two") == "number"`.

Spec-reader controls (P-2), all measured: no heading → 0 rows, one vacuity
violation `matched nothing`; nine rows → `9 preset row(s) ... expected
exactly 10` listing the words; empty third cell → `the preset "Wait" has no
phases in its third cell`; empty backticks → `a preset row has an empty
word`; header, separator, a row above the heading and a row after the next
heading not read; a `## 5` heading also ends the section; case, inner
spaces, comma-split and line number kept.

**One expectation revised in RED, on measurement.** I expected `rowsSwapped`
to fire P-3 as well as AC-1. It fires AC-1 only, and that is the check
behaving correctly: the stub keeps `key` in Contract order while swapping the
words, and P-3 pins `key` **by position**, not by word. The control's
expectation was corrected to `{ AC-1 }` and its name says why. No check was
changed.

### Deferred verifications — declined in RED

- **D-1** (mutate the real module `"Go"` → `"Go now"`): **not run.** The
  module does not exist; nothing to mutate. Its shape is the `wordChanged`
  control above, measured against the stub. Owner: GATES.
- **D-2** (drop `"Post"` from `Well played`): **not run**, same reason. Shape:
  `phaseDropped`. Owner: GATES.
- **D-3** (`"Help"` → `"Help!"`): **not run**, same reason. Shape:
  `terminalPunctuation`. Owner: GATES.

None of the three is claimed. When GATES runs them with `scripts/mutate.sh`
on `src/shared/channel/Presets.luau`, the expected red is one AC-1 failure
naming `Go now`/`Go` (D-1), one AC-1 **and** one AC-5 failure naming `Well
played` (D-2 — if the expression leaves `{}`; AC-1 only if it leaves another
legal phase), and one AC-1 **and** one AC-4 failure naming `Help!` (D-3).

### Timeouts and budgets

The Lune runner has no per-test timeout and no hooks, so there is nothing to
budget in these files. Cost: the whole suite is 469 s under the `unit` gate
on this machine (local; CI not measured for this story); the five new files
add two `GatedFs` reads (both memoised, the `classify.sh --gated` spawn is
shared across the run) and no loops over generated data. No `slow` line is
needed.

### Callers re-check

`rg -n "Presets\b|PresetSpec" src tests` on the tree at `5e6d97b` before
writing: no matches (exit 1). The only references now are the five files
above.

### Discovered, for the implementer

- P-2's "before the next `###`" is implemented as "before the next markdown
  heading of any level" (`^#+%s`). The next heading is `### 4.3`, so on the
  current document the two readings are identical; the broader one stops a §5
  table being read as presets if §4.3 were ever removed. Not a Contract
  amendment — the Contract's behaviour on the real document is unchanged.
- AC-1 compares `phases` as an **ordered list** against the document's cell
  order, which is what "the same phases per row" pinned most cheaply. If the
  design later wants set semantics, that is a one-line change in
  `PresetContract.tableMatchesTheSpec`, in RED.
- `Presets.ALL` must be a *sequence* (no holes) for `#ALL`, `ipairs`-style
  iteration and `ALL[i]` to agree; `table.freeze` on a literal list does
  that.

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


**PO decisions at PLANNED → RED (lead-po, 2026-10-05).**

1. **Gate.** The artifact (`src/shared/channel/Presets.luau`) is read by `unit`
   (`lune run test`), which is `required`; the spec it is compared against,
   `mechanics.md`, is in `unit`'s `covers` (project.conf). `required_gates`
   stays empty.
2. **Epic done-when #2** ("the preset table matches §4.2 exactly and passes C1,
   C2, C6 and C8 as tests") is AC-1 – AC-4 exactly. No gap.
3. **CHAN-001's PO-1** (build presets now, or wait for Roblox's announced preset
   service) does not gate this story: the table is the design's content, which
   any delivery route — this project's or Roblox's — needs. It gates `CHAN-004`.

**RED verification (lead-po, 2026-10-05, against `357e89f`).**

- `lune run test` → `1164 passed, 8 failed` in 108 s. All 8 are
  `tests/shared/presets_test.luau`, each `src/shared/channel/Presets.luau did not
  load` - the module is missing, the right failure. The 31 controls pass. (RED
  reported 469 s for `unit` under the gate; re-measured at 108 s plain and 111 s
  under `--fast`, so that was machine load, not the suite.)
- `bash scripts/gates.sh --fast` after the RED commit: `PASS format (181)`,
  `PASS lint (181)`, `PASS typecheck (29)`, `FAIL unit (111s)` on exactly those
  8, `PASS build`, `FAIL harness` with `project-counters: 28 passed, 12 failed`
  - every failure `expected 182 / actual 181`, `30/29` or `9/8` and their
  untracked/ignored variants: the predicted post-GREEN baselines (P-6). The
  stray-file precondition passes. (The suite's labels say "92 files"; that is a
  fixed string in the test name, not the measured count.)
- Read `presets_test.luau` (one test per AC-1 … AC-5, P-3, P-4, P-5) and the
  denylist (`one` excluded with the T12 citation, as the contract decided).
