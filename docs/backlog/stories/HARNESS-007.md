---
id: HARNESS-007
title: The roblox-luau profile still teaches the counter HARNESS-006 removed
slug: the-roblox-luau-profile-still-teaches-th
epic: 
type: chore
status: in-review
phase: REVIEW
branch: story/HARNESS-007-the-roblox-luau-profile-still-teaches-th
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

`HARNESS-006` fixed the three counters in this project's
`.claude/harness/project.conf`. It did not touch the document those counters were
copied **from**, and that document is still the thing a new project reads:
`.claude/skills/stack-profiles/reference/roblox-luau.md`.

The profile is not careless — it is the opposite, and that is what makes this
worth a story. It documents four real hazards it had already been bitten by: a
git pathspec where `**/` never matches zero directories, `git ls-files` reading
the index rather than the disk, a `grep -E` stage that exits 1 on an empty tree
and takes the whole `&&` chain with it, and `doctor.sh` reading the first token
of a gate command as the tool name. Every one of those is right, measured, and
still right after `HARNESS-006`.

**The defect is in the instruction those hazards hang off.** The profile says:

> That makes `evidence` harder here than in any other profile, and it is solved
> the same way each time: **make the gate command count its own inputs.**

*The gate command* counts its own inputs. The **tool** is never asked. And the
abstraction the profile then defines makes the second enumeration structural
rather than accidental:

    Let `COUNT(dirs)` stand for the counting pipeline above:
        n=$(git ls-files -- <dirs> | while ... done | wc -l)

    gate | lint | required | . | selene src tests lune && COUNT(src tests lune) && echo "selene over $n files"

`COUNT` takes the path list as an argument, so every gate written from this
profile names its target **twice, by construction**. That is the `HARNESS-006`
defect, and this file is where new projects get it.

One line above it, the profile already knows the answer and applies it exactly
once: *"Every gate below uses this pattern except `unit`, which has a real runner
that counts for itself."* `HARNESS-006` is that sentence generalised — prefer the
tool's own count; derive one only where the tool has none, and then from the same
target the tool was handed.

**Which required gate would fail if this story's artifact broke:** none in
`project.conf`, and that is a fact rather than an oversight — the artifact is a
markdown reference, which no gate reads. The guard is
`.claude/tests/**` under `scripts/selftest.sh`, which runs inside CI's required
`gates` job before `gates.sh`. Same answer, same evidence, as `HARNESS-006`
decision 1; `required_gates` stays empty for the same reason.

## Acceptance criteria

- **AC-1** — Given the `roblox-luau` profile, when its `format` gate command is
  read, then the count it prescribes is **`stylua`'s own** (`--check -v`, counting
  `debug: formatted` lines), not a `git ls-files` enumeration beside it.
- **AC-2** — Given the profile's `lint` and `typecheck` gate commands, when each
  is read, then the target path list appears **exactly once** in the command and
  is referenced by the counter rather than repeated.
  *Control:* the current `COUNT(src tests lune)` form names it twice and **must**
  fail this.
- **AC-3** — Given the profile's counting pipeline, when the pathspec is read,
  then it is `git ls-files --cached --others --exclude-standard`, never bare
  `git ls-files`.
  *Control:* the current text prescribes bare `git ls-files` and **must** fail
  this. `find` must also fail it — it sweeps in gitignored build output
  (`HARNESS-006` measured 39 against the tools' 38).
- **AC-4** — Given the profile's prose, when the instruction that introduces the
  counters is read, then it says to prefer **the tool's own count** and to derive
  one only where the tool has none.
  *Semantics:* AC-1 to AC-3 fix three commands. This fixes the sentence that
  generated them, and without it the next gate added to the profile reintroduces
  the defect.
- **AC-5** — Given the profile's four documented hazards (the `**/` pathspec, the
  index-not-disk read, the pipefail-on-empty stage, the first-token rule), when
  the rewritten profile is read, then **all four are still stated and still
  correct**.
  *Control:* a rewrite that drops any of them must fail. They are why the
  surviving `lint`/`typecheck` counters look as they do, and `HARNESS-006`
  confirmed every one of them independently.
- **AC-6** — Given the shipped `.claude/harness/project.conf`, when its three
  gate commands are compared with the profile's, then they agree in **shape** —
  the profile teaches what this project actually does.
  *Semantics:* the profile's whole job is to be copied. A profile that disagrees
  with the one project known to have got it right is worse than no profile.
- **AC-7** — Given a future edit that reintroduces a second enumeration into the
  profile, when the harness self-test runs, then it **fails and names the
  offending line**.
  *Control:* reverting the profile to today's text must make this fail. Without
  it AC-1 to AC-4 are true only on the day they are written.

## Contract

Changes `.claude/skills/stack-profiles/reference/roblox-luau.md` and adds a guard
under `.claude/tests/`. **No change to `.claude/harness/project.conf`** — that
file is already correct as of `HARNESS-006`, and this story's AC-6 asserts the
profile catches up to it, never the reverse.

### Ownership, checked — it decides the whole scope

`scripts/refresh-harness.sh` **replaces** `.claude/skills` and `.claude/tests`
wholesale for every file upstream ships, and **keeps** any file upstream does not.
So "where does the fix live" is not a preference, it is a question with a
verifiable answer:

    $ ls ../agentic-dev-harness/.claude/skills/stack-profiles/reference/
    environments.md  godot.md  new-profile.md  node-typescript.md
    python-uv.md     rust-cargo.md            web-static.md

    $ ls ../agentic-dev-harness/.claude/tests/
    ... gates.test.sh  new-story.test.sh  plan.test.sh  profiles.test.sh ...

| File | Upstream ships it? | On refresh | Therefore |
|---|---|---|---|
| `reference/roblox-luau.md` | **no** | KEPT — ours | fix it here; the fix is durable |
| `.claude/tests/project-counters.test.sh` | **no** | KEPT — ours | a guard may live here |
| `reference/new-profile.md` | **yes** | REPLACED | an edit here evaporates — out of scope |
| `.claude/tests/profiles.test.sh` | **yes** | REPLACED | a check added here evaporates — out of scope |

`roblox-luau.md` is in fact the very file `refresh-harness.sh`'s own header warns
about: *"a wholesale replace of `.claude/skills` deletes a project's OWN stack
profile - the one in the way was 17 KB and cited by four documents, and nothing
would have said a word."* That is this file. It is ours, and a refresh keeps it.

### The shape to teach, taken from the shipped conf rather than reinvented

`HARNESS-006` already measured all of this; the profile is being brought into line
with a working implementation, not redesigned. Read the three `gate` lines out of
`.claude/harness/project.conf` and teach their shape:

- **`format`** — one `stylua --check -v` run, counted from its own
  `^debug: formatted ` lines (stderr, hence `2>&1`; anchored on the prefix and not
  on a path shape, because Windows prints `src\shared\x.luau` and Linux
  `src/shared/x.luau` and both must count the same). Status from
  `${PIPESTATUS[0]}`, not the pipeline's. The awk pass **passes non-debug output
  through**, so a real `Diff in ...` still reaches the log — `grep -c` swallows it.
  On an empty target it prints `over 0 files` and exits 0, which the evidence
  regex refuses.
- **`lint` and `typecheck`** — no per-file output exists
  (`selene --display-style Json2` emits one Summary; `luau-lsp analyze` emits
  none), so the count stays derived, from `${GATE_*_TARGET:=...}` named once and
  handed to both tool and counter, with
  `git ls-files --cached --others --exclude-standard`.
- **Keep the four hazards** (AC-5) and add the two `HARNESS-006` found:
  `grep -c` exits 1 on an empty count, and a `T="..."; tool $T` prefix breaks
  `doctor.sh`'s first-token rule just as `n=$(git ...` does.
- **Record the `:=` trapdoor**: an exported `GATE_LINT_TARGET` beats the default.
  Accepted in `HARNESS-006` because it narrows the tool and the counter *together*
  — the gate then checks less and says so honestly, which is a lesser fault than
  reporting 38 while reading 7.

### The guard (AC-7)

A project-owned suite, because `profiles.test.sh` is upstream's. Extending
`.claude/tests/project-counters.test.sh` is the obvious home — it already parses
gate commands — but it is named for `project.conf`, and a profile is a different
subject. **RED decides and says why in `## Test plan`**, subject to one hard
constraint: it must live in a file upstream does not ship, or a refresh deletes
it and AC-7 becomes decoration.

What it asserts is a *property of the text*, so it needs no toolchain: no gate
command in the profile names its target twice; no counting pipeline uses bare
`git ls-files` or `find`. It must name the offending line.

**Do not assert the profile and `project.conf` are byte-identical.** AC-6 is
agreement in shape; the profile uses `<dirs>` placeholders and prose, and a
byte comparison would fail on the first legitimate divergence and be deleted by
the next person.

### This story does NOT bump `.claude/harness/VERSION` — an earlier pin here was wrong

**Withdrawn 2026-09-17.** A previous version of this section instructed GREEN to
bump `.claude/harness/VERSION`, on the grounds that harness 30's
`check-boundaries.sh` refuses a PR touching `.claude/` without one. **That was a
Lead PO error and the instruction is withdrawn.** It is recorded rather than
deleted because an instruction that names a mechanism is a claim, and this one
was made without checking that the mechanism fires here.

The check is scoped by two conditions, not one
(`scripts/check-boundaries.sh`, "3a-bis"):

    if [ -z "$sid" ] && ! grep -qE '^BOOTSTRAPPED=yes' .claude/harness/project.conf

- `[ -z "$sid" ]` — **not a story branch.** Downstream work always is; an upstream
  harness round never is.
- and the repo is **unbootstrapped**. Every real project sets `BOOTSTRAPPED=yes`;
  only the template does not.

This project is bootstrapped and `HARNESS-007` is a story, so **the check cannot
fire for it.** The script's own comment says so in as many words: *"This must
never fire in a project BUILT on the harness, where `.claude/` is edited
routinely - project.conf, paths.conf, .gitignore - by people who are not upstream
and have no version to stamp."*

**Proved by a story that had already run it.** `SEAT-001` changed
`.claude/harness/project.conf` (the `unit` floor, 175 → 197) on a story branch,
and `check-boundaries.sh` passed all ten checks with no VERSION bump and no
complaint - locally and on CI.

**Where the wrong claim came from**, since it is the more useful half: the failure
text was read out of `boundaries.test.sh`'s **fixture** output, where the fixture
repo is deliberately unbootstrapped and has no story, and generalised to this
repo without checking the guard. The fixture was doing its job; the reader was
not.

**So GREEN does nothing about VERSION.** Bumping it would be actively wrong —
this project has no upstream version to stamp, and the next
`refresh-harness.sh` would overwrite the claim anyway.

### Oracle partition

| AC | Kind | Instruction to RED |
|---|---|---|
| AC-1, AC-2, AC-3, AC-6 | **Mechanical** | The target shape is in the shipped `project.conf`. Read it out; do not redesign it. |
| AC-4, AC-5 | **Mechanical, with controls** | Properties of prose. Assert the claims are present, not their wording — an assertion on exact phrasing breaks on the first honest edit. |
| AC-7 | **Mechanical, with a control** | The control is reverting the profile to today's text. |

**Test-only dependencies:** none. Bash, awk, coreutils; the guard reads a
markdown file. No toolchain, unlike `project-counters.test.sh`.

### No signature changes

Nothing exports anything and no command is executed by this story's artifact. The
profile is read by people and agents, not run.

### The phase lock enforces nothing here either

`.claude/skills/**` and `.claude/tests/**` both classify as `harness`, writable in
every phase — same as `HARNESS-006`. RED writes the guard and does not touch the
profile; GREEN rewrites the profile and does not touch the guard; the orchestrator
reads the diff at each boundary, because nothing else will.

### Three inputs the story was filed without — added at PLANNED by the Lead PO

Each was verified against the tree today (2026-09-17); see `## Notes` decisions
1-4 for the commands. They are contract, not commentary: RED builds against them.

**(a) A required `harness` gate now exists, and it runs exactly one suite.**
`HARNESS-008` added `gate | harness | required | . | bash
.claude/tests/project-counters.test.sh`. That is new since this story was filed,
and it makes the guard's placement a question with a consequence rather than a
matter of taste:

| Guard lives in | Runs under `gates.sh --fast` | Runs in CI | Needs the Roblox toolchain |
|---|---|---|---|
| `project-counters.test.sh` | **yes**, via the `harness` gate | yes | **yes — inherited** |
| a new `.claude/tests/*.test.sh` | no | yes, via `selftest.sh` | no |

The third column decides it. `project-counters.test.sh` shells out to stylua,
selene, rojo and luau-lsp and treats a missing tool as a hard failure, never a
skip (its own header says so). This story's guard is a property of *text* and
declares no toolchain at all. Folding it in would make a markdown assertion
unrunnable because `luau-lsp` is absent — a vacuous-by-environment failure of
exactly the kind `project-counters` exists to abolish. `HARNESS-008`'s own stated
criterion for the `harness` gate points the same way: it admits only the suite a
**product** story can break, and no product story touches `.claude/skills/**`.

**So: a new file, and `required_gates` stays empty.** RED still chooses the name
and still writes the reasoning in `## Test plan`, but the placement is settled
here, and the constraint is now two, not one: upstream must not ship it, **and**
it must run on bash, awk and coreutils alone.

The price, stated so nobody is surprised by it: `gates.sh --fast` will **not**
run this guard. The orchestrator runs `bash scripts/selftest.sh <suite>` by hand
at the end of RED and again at the end of GREEN. Do not "fix" this by adding the
suite to the `harness` gate — that is a gate change, and it needs `## Gate
probes` and a reason better than convenience.

**(b) AC-6's "agree in shape", made mechanical.** AC-6 must not degrade into
"a human read both and felt they matched". It is discharged by three structural
comparisons between the profile's prescribed command and `project.conf`'s, and by
nothing else:

1. `format` — both take their count from `stylua`'s own output, anchored on
   `^debug: formatted `, and both take status from `${PIPESTATUS[0]}` rather than
   the pipeline's.
2. `lint` and `typecheck` — both name the target through a single
   `${GATE_*_TARGET:=...}` assignment that the counter then reads, and the
   literal path list occurs **once** in each command.
3. Both counters use `git ls-files --cached --others --exclude-standard`.

Nothing about wording, ordering, comments, or the `<dirs>` placeholders the
profile legitimately uses where the conf has real paths.

**(c) The trap in AC-2 and AC-3: prose is not a command.** The four hazards AC-5
requires the profile to keep are *about* the defective forms. Line 51 today reads
"**`git ls-files` reads the index, not the disk**" — a bare `git ls-files`, in
the sentence explaining why not to use one. A guard that greps the whole file for
`git ls-files` without `--cached` fails the corrected profile **because AC-5 was
satisfied**, and the natural repair is to delete the hazard, which is the one
outcome this story must not produce.

So AC-2's and AC-3's checks are scoped to **prescribed gate commands** — lines
that are, or are indented examples of, `gate | <id> | ...` — and never to prose.
Getting this backwards makes AC-3 and AC-5 mutually unsatisfiable. RED states in
`## Test plan` how it draws that boundary, and asserts the boundary itself: the
suite must stay green on a profile that still contains the four hazard
paragraphs verbatim.

**(d) `EPIC-00` is DONE and cites this file as its evidence.** Two clauses of a
closed epic's done-when table rest on text inside `roblox-luau.md`, and a tidy
rewrite drops both without a word:

- the `Verified 2026-09-15` banner at line 10, naming Rokit 1.2.0, Rojo 7.7.0,
  Wally 0.3.2, Lune 0.10.5, Selene 0.31.0, StyLua 2.5.2 and luau-lsp 1.69.0,
  with its `Linux verified 2026-09-16` addendum and its standing
  "macOS is still unverified" (`EPIC-00`, done-when row 3);
- the Rokit `curl` install line under **Prerequisites**, whose `UNVERIFIED`
  marker `EPIC-00` resolved rather than deleted (`EPIC-00`, "the two inline
  markers").

GREEN keeps both. This is the same class of obligation as AC-5 and RED covers it
the same way — assert the *claims are present*, not their wording.

## Deferred verifications

<!-- Nothing is deferred. The artifact exists and is already wrong, so every
     control is producible in RED: a guard can be run against today's profile
     and watched to name the offending lines. The consequence is the one
     rules.md names and HARNESS-006 lived through - every assertion runs against
     text that already exists, so any assertion green on arrival is earned by
     mutating the profile through scripts/mutate.sh and pasting the output into
     ## Regressions. -->

## Model guidance

**Resolved model of every dispatch, by name:**

| Phase | Agent | `models.conf` plan | **Resolved** | Why, where they differ |
|---|---|---|---|---|
| PLANNED | lead-po | opus | **`claude-opus-5`** | as planned |
| RED | test-developer | fable | **`claude-opus-5`** | the `except \| RED \| unenforced` row applies; `plan.sh` did not fire it. See PO decision 4. Confirmed at dispatch by the agent: `bash scripts/phase.sh show` printed `Model for RED: fable` and the dispatch resolved to `claude-opus-5`, so this was an override, as decision 4 intended. |
| GREEN | feature-developer | opus | **`claude-opus-5`** | as planned. No exception applies: the `unenforced` row is RED-only, and GREEN never moves by policy. |
| GATES | feature-developer | opus | **`claude-opus-5`** (orchestrator-run; no dispatch needed — no gate failed) | as planned |
| REVIEW | lead-po | opus | **`claude-opus-5`** | as planned |

Two things to brief carefully.


**AC-5 is the one a rewrite quietly loses.** The four hazards are the reason the
surviving counters look strange, and a tidy-minded rewrite deletes them as
clutter. They are load-bearing: each was paid for by a real failure, and
`HARNESS-006` re-confirmed all four. Say that the rewrite is *additive to the
reasoning* even where it replaces the commands.

**AC-7's guard must live in a file upstream does not ship.** State the refresh
rule in the dispatch rather than hoping it is inferred — the natural instinct is
to add a check to `profiles.test.sh`, which is upstream's and is deleted on the
next refresh, taking the guard with it and leaving the story looking done.

## Out of scope

- **`.claude/harness/project.conf`.** Already fixed by `HARNESS-006`. If this
  story finds a disagreement, the profile is wrong, not the conf — unless the
  disagreement is a real defect in the conf, which is a finding to raise, not to
  fix here.
- **`reference/new-profile.md`, where the general principle belongs.** Its
  *"Writing the evidence lines"* section is where a future profile author learns
  this, and it is **upstream's file**: an edit here is destroyed by the next
  `refresh-harness.sh`, silently, because REPLACED is the expected outcome and
  nobody re-reads it. Same for a new check in `profiles.test.sh`. Both belong in
  a change to `../agentic-dev-harness`, reported upstream rather than patched
  locally. Recorded so the omission is a decision.
- **The other six profiles.** Surveyed: none carries this shape —
  `grep -ln 'git ls-files\|wc -l'` over `reference/*.md` matches `roblox-luau.md`
  alone. They lean on runners that count for themselves, which is the thing this
  ecosystem has none of.
- **Any change to how `gates.sh` reads evidence, or to any `floor`.** Untouched.

## Test plan

### The file, and why that name

**`.claude/tests/profile-counters.test.sh`** — one new file, nothing else.

The two constraints in `## Contract` (a) decide it, and both were checked rather
than assumed:

    $ ls ../agentic-dev-harness/.claude/tests/
    _lib.sh  boundaries.test.sh  ci-local.test.sh  classify.test.sh
    doctor.test.sh  gate-reminder.test.sh  gates.test.sh  lib.test.sh
    mutate.test.sh  new-story.test.sh  phase-guard.test.sh  phase.test.sh
    plan.test.sh  profiles.test.sh  refresh.test.sh  settings.test.sh
    sigpipe.test.sh

`profile-counters.test.sh` is not there, so a refresh KEEPS it. `profiles.test.sh`
is, so a check added there evaporates. And it declares no toolchain: bash, awk,
coreutils, two `cat`s. It is therefore not folded into `project-counters.test.sh`,
whose header makes a missing `luau-lsp` a hard failure — a markdown assertion must
not become unrunnable because an analyser is absent.

The **name** pairs with `project-counters` deliberately: same subject (where a
gate's file count comes from), different artifact. `project-counters` pins this
project's `project.conf` by **running** it; this suite pins the **document** that
conf was copied from, by **reading** it. A reader who knows one knows the other.

Reachability, verified: `scripts/selftest.sh:20` globs
`"$ROOT"/.claude/tests/*.test.sh`, and `.github/workflows/gates.yml:107-108` runs
`bash scripts/selftest.sh` in the required `gates` job. It is named by no `gate`
line, so `gates.sh --fast` does not run it — as `## Contract` (a) requires.

### The boundary, stated exactly (Contract (c))

A **prescription** is a line whose first pipe-field is `gate`:
`gate | <id> | <req> | <dir> | <command>`, indented or not. Those are the lines a
project copies into its `project.conf`. **AC-1, AC-2 and AC-3 look at nothing
else.** Everything else is prose — paragraphs, bullets, inline backticks, and
indented code blocks that are not `gate` lines.

The two lines the contract asked me to place deliberately:

| Line | Side | Why |
|---|---|---|
| ~44, the worked "obvious version" counter-example | **prose** | a paragraph whose entire job is to say "this is wrong". In scope it would fail the corrected profile. |
| ~75, the `COUNT(dirs)` macro definition | **prose** | an indented code block, but a *definition*, not a prescription. |

Putting the macro on the prose side opens a hole — a profile could hide a bare
`git ls-files` there and delegate to it from a clean-looking gate line. It is
closed by a **positive** requirement rather than by widening the scope:
`ck_counter_present` requires each `lint` and `typecheck` **gate command** to
contain `git ls-files --cached --others --exclude-standard` *inline*. A gate line
that delegates has no pipeline and is an offence. The macro is then unusable
rather than forbidden, which is why the suite does not care whether it survives
as documentation.

Scope applies per **line**, not per gate id: today there are **two** `gate | lint`
lines (40, the "verified form", and 78, the gate table). Both are prescriptions
and both are checked. The consequence for GREEN is in the handoff.

**The boundary is asserted, not claimed.** Three cases at the end of the suite:
a synthetic document carrying a bare `git ls-files`, a `find` sweep, a
`COUNT(...)` and a `**/` pathspec *in prose* is clean; today's real profile with
**only its three gate lines replaced by `project.conf`'s** is clean, hazard
paragraphs and line 44 and the macro all present verbatim; and that same document
still states all four hazards, so "clean" cannot be clean-by-deletion.

### Level

Text assertions over two files, run as a harness suite. There is no cheaper level
and no more expensive one that would falsify anything extra: the artifact is a
markdown reference that no gate reads and nothing executes. An integration or
end-to-end level does not exist for it.

### What each assertion covers

| # | Assertion | AC | Red today |
|---|---|---|---|
| 1-2 | the profile and `project.conf` exist | precondition | no |
| 3 | the profile prescribes a `format`, a `lint` and a `typecheck` command | precondition — stops every scan below being vacuously clean | no |
| 4 | `project.conf` prescribes the same three | precondition | no |
| 5 | every `format` command counts stylua's own `debug: formatted` lines | AC-1 | **yes** |
| 6 | every `format` command takes status from `${PIPESTATUS[0]}` | AC-1 | **yes** |
| 7 | no `format` command enumerates beside the tool | AC-1 | **yes** |
| 8 | every `lint` command names its target through one `${GATE_LINT_TARGET:=...}` the counter reads | AC-2 | **yes** |
| 9 | every `lint` command names the target path list exactly once | AC-2 | **yes** |
| 10-11 | the same two for `typecheck` / `${GATE_TYPE_TARGET:=...}` | AC-2 | **yes** |
| 12 | no gate command uses a bare `git ls-files` | AC-3 | **yes** |
| 13 | no gate command enumerates with `find` | AC-3 | no (vacuous today; earned by #12 sharing the scanner) |
| 14-15 | `lint` and `typecheck` carry the counting pipeline inline | AC-3 | **yes** |
| 16 | the profile no longer says "make the gate command count its own inputs" | AC-4 | **yes** |
| 17 | the profile says to prefer the tool's own count | AC-4 | **yes** |
| 18 | the profile says a count is derived only where the tool has none | AC-4 | **yes** |
| 19-22 | the four hazards, **one assertion each**, so a failure names which | AC-5 | no — probed |
| 23 | the `Verified` banner still names all seven tools and both platform verdicts | EPIC-00 (d) | no — probed |
| 24 | ... and they are one banner, not scattered | EPIC-00 (d) | no — probed |
| 25 | the Rokit `curl` line survives **under Prerequisites** | EPIC-00 (d) | no — probed |
| 26-29 | `project.conf`'s own three shapes, asserted directly | AC-6 oracle | no — probed |
| 30 | comparison 1 — `format` | AC-6 | **yes** |
| 31 | comparison 2 — `lint`/`typecheck` target naming | AC-6 | **yes** |
| 32 | comparison 3 — the pathspec | AC-6 | **yes** |
| 33-34 | a `COUNT(<paths>)` prescription is named with its line number and its text | AC-7 | no — control |
| 35-37 | a second enumeration added back to an already-corrected command is named, with the count and the list | AC-7 | no — control |
| 38 | prose carrying every defective form is clean | boundary | no — control |
| 39 | today's profile with only its gate lines corrected is clean | boundary | no — probed |
| 40 | ... and still states all four hazards | boundary | no — probed |

`count_occurrences` from `project-counters.test.sh` was read and its **idea**
reused verbatim (literal, non-overlapping, `case`-based, no fork). It is copied
rather than imported for one reason: that suite shells out to four tools at load
time, so importing it would drag the whole toolchain requirement into a markdown
assertion, which is the thing `## Contract` (a) forbids. `_lib.sh` is upstream's,
so it is not a home for it either. Mine sets `OCCUR` instead of echoing — see the
runtime note below.

### AC-6 is three comparisons, and the oracle is a literal

Each comparison's expected value is a **literal** string (`conf=ok/ok
profile=ok/ok`), never `project.conf`'s own verdict. Reading the oracle out of the
file being compared against would make a regression in `project.conf` read as
agreement — the same trap `project-counters.test.sh` documents about its counts.
Assertions 26-29 then pin the conf side on its own, so a regression there is named
rather than inferred. No byte comparison anywhere.

### Wording is never asserted

AC-4, AC-5 and the EPIC-00 claims accept a **set** of phrasings, listed in the
check and printed in the failure message, and require the tokens of a claim to sit
within a window of consecutive lines rather than anywhere in the document. A
window, not a bullet or a paragraph, so GREEN may re-present the hazards however
it likes; not the whole document, because `pipefail` appearing anywhere would
satisfy a deleted hazard.

**Two alternations were tightened because a probe caught them.** `matches zero`
(hazard 1) and `first argument of each gate` (hazard 4) are both satisfied by a
sentence stating the *opposite* of the hazard, and the hazard-4 probe
(`first token` → `first argument`) duly left the suite green. A needle its own
mutation satisfies is a test that cannot fail. Both are gone.

### Runtime

**30.5 s → 9.6 s**, measured on this machine (Windows 11, Git Bash), same 24/16
verdict before and after. The first version put `$(occurrences ...)` and
`$(gate_cmd_of ...)` on the hot path — roughly 900 subshells to read two text
files, at ~30 ms a fork on Windows. `occurrences`, `gate_cmd_of` and `count_gates`
now set out-variables, and each document's prescription list is parsed **once**
into a `GL_*` variable rather than per scan. This is the cost
`project-counters.test.sh`'s header warns about, in a suite that does no I/O at
all. Do not reintroduce a fork inside `scan_gates`.

No timeout applies: `selftest.sh` imposes none and this suite is named by no
`gate` line, so there is no framework budget to sit under. It is nonetheless the
one thing that would make the suite unwelcome, hence the measurement.

### Test-only dependencies

None, as `## Contract` predicted. No manifest was touched.

## Handoff: RED -> GREEN

### The command

    bash .claude/tests/profile-counters.test.sh          # the suite alone, ~10 s
    bash scripts/selftest.sh profile-counters            # via the path CI uses
    bash scripts/selftest.sh                             # all 18 harness suites

`gates.sh --fast` does **not** run it, by design (`## Contract` (a)). Run
`selftest.sh` by hand at the end of GREEN.

### Files touched in RED

| File | What |
|---|---|
| `.claude/tests/profile-counters.test.sh` | **new**, the whole guard |
| `docs/backlog/stories/HARNESS-007.md` | `## Test plan`, this handoff, `## Regressions` |

Nothing else. `.claude/skills/stack-profiles/reference/roblox-luau.md` and
`.claude/harness/project.conf` were **mutated and restored** by `scripts/mutate.sh`
(13 times, every restore verified byte-for-byte by `cmp`) and are otherwise
untouched — `git status` shows neither.

### Current failure: 16 red, 24 green

    profile-counters: 24 passed, 16 failed

It is the right failure. Every one of the 16 is an assertion about the profile's
prescribed commands or prose, naming the profile line it read; not one is a
syntax error, a missing file, or an import. Verbatim:

```
  AC-1  the format gate takes its count from the tool
    FAIL every format gate command counts stylua's own 'debug: formatted' lines
         expected:
         actual:   line 77: the format gate does not take its count from stylua's own output: no 'debug: formatted ' in the command
             gate | format    | optional | . | stylua --check src tests lune && COUNT(src tests lune) && echo "stylua over $n files"
    FAIL every format gate command takes its status from ${PIPESTATUS[0]}
         expected:
         actual:   line 77: the format gate does not take its exit status from ${PIPESTATUS[0]}, so its correctness is borrowed from the runner's shell options
             gate | format    | optional | . | stylua --check src tests lune && COUNT(src tests lune) && echo "stylua over $n files"
    FAIL no format gate command enumerates its inputs beside the tool
         expected:
         actual:   line 77: the format gate counts its inputs BESIDE the tool: the command contains 'COUNT(', and stylua --check -v already prints one line per file it read
             gate | format    | optional | . | stylua --check src tests lune && COUNT(src tests lune) && echo "stylua over $n files"

  AC-2  lint and typecheck name their target exactly once
    FAIL every lint gate command names its target through a single ${GATE_LINT_TARGET:=...} the counter reads
         expected:
         actual:   line 40: the target is not named through a single '${GATE_LINT_TARGET:=...}': found 0, want exactly 1
             gate | lint | required | . | selene src tests lune && n=$(git ls-files -- src tests lune | while IFS= read -r f; do case "$f" in *.luau) if [ -e "$f" ]; then echo x; fi ;; esac; done | wc -l) && echo "selene over $n files"
         line 78: the target is not named through a single '${GATE_LINT_TARGET:=...}': found 0, want exactly 1
             gate | lint      | required | . | selene src tests lune && COUNT(src tests lune) && echo "selene over $n files"
    FAIL every lint gate command names the target path list exactly once
         expected:
         actual:   line 40: no '${GATE_LINT_TARGET:=...}' to read the target list out of, so the tool's target and the counter's cannot be the same by construction
             gate | lint | required | . | selene src tests lune && n=$(git ls-files -- src tests lune | while IFS= read -r f; do case "$f" in *.luau) if [ -e "$f" ]; then echo x; fi ;; esac; done | wc -l) && echo "selene over $n files"
         line 78: no '${GATE_LINT_TARGET:=...}' to read the target list out of, so the tool's target and the counter's cannot be the same by construction
             gate | lint      | required | . | selene src tests lune && COUNT(src tests lune) && echo "selene over $n files"
    FAIL every typecheck gate command names its target through a single ${GATE_TYPE_TARGET:=...} the counter reads
         expected:
         actual:   line 79: the target is not named through a single '${GATE_TYPE_TARGET:=...}': found 0, want exactly 1
             gate | typecheck | required | . | rojo sourcemap default.project.json --output sourcemap.json && test -s globalTypes.d.luau && luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --base-luaurc=.luaurc --ignore='Packages/**' src 2>&1 | awk '{print} /^\[ERROR\]|Sourcemap parsing failed/{bad=1} END{exit (bad?1:0)}' && COUNT(src) && echo "analyze over $n files"
    FAIL every typecheck gate command names the target path list exactly once
         expected:
         actual:   line 79: no '${GATE_TYPE_TARGET:=...}' to read the target list out of, so the tool's target and the counter's cannot be the same by construction
             gate | typecheck | required | . | rojo sourcemap ... && COUNT(src) && echo "analyze over $n files"

  AC-3  the counting pipeline uses --cached --others --exclude-standard
    FAIL no gate command in the profile uses a bare 'git ls-files'
         expected:
         actual:   line 40: uses a bare 'git ls-files' (1 occurrence(s), only 0 carrying --cached --others --exclude-standard): bare ls-files reads the index and misses a story's own new files until they are committed
             gate | lint | required | . | selene src tests lune && n=$(git ls-files -- src tests lune | ... | wc -l) && echo "selene over $n files"
    FAIL every lint gate command carries the counting pipeline inline
         expected:
         actual:   line 40: has no counting pipeline in the command itself: no 'git ls-files --cached --others --exclude-standard'. A gate that delegates its count to a macro can name its target twice out of sight
             gate | lint | required | . | selene src tests lune && n=$(git ls-files -- src tests lune | ... | wc -l) && echo "selene over $n files"
         line 78: has no counting pipeline in the command itself: no 'git ls-files --cached --others --exclude-standard'. A gate that delegates its count to a macro can name its target twice out of sight
             gate | lint      | required | . | selene src tests lune && COUNT(src tests lune) && echo "selene over $n files"
    FAIL every typecheck gate command carries the counting pipeline inline
         expected:
         actual:   line 79: has no counting pipeline in the command itself: no 'git ls-files --cached --others --exclude-standard'. ...
             gate | typecheck | required | . | rojo sourcemap ... && COUNT(src) && echo "analyze over $n files"

  AC-4  the prose prefers the tool's own count
    FAIL the profile no longer says to make the gate command count its own inputs
         expected:
         actual:   37:the same way each time: **make the gate command count its own inputs.** Do not
    FAIL the profile says to prefer the tool's own count
         no run of 4 consecutive lines carries this claim.
         Any ONE phrasing per `;;` group satisfies it - the wording is GREEN's choice:
           group: tool's own@@tool's own@@'s own count@@'s own output@@prefer the tool@@read the count out of the tool@@the tool already counts
    FAIL the profile says a count is derived only where the tool has none
         no run of 6 consecutive lines carries this claim.
         Any ONE phrasing per `;;` group satisfies it - the wording is GREEN's choice:
           group: derive@@derived@@deriving@@derivation
           group: has none@@has no count@@no count of its own@@no per-file@@does not print@@prints no@@emits none

  AC-6  the profile and project.conf agree in shape
    FAIL comparison 1 - format: both count from 'debug: formatted' and both take status from ${PIPESTATUS[0]}
         expected: conf=ok/ok profile=ok/ok
         actual:   conf=ok/ok profile=BAD/BAD
    FAIL comparison 2 - lint/typecheck: both name the target through a single ${GATE_*_TARGET:=...}, path list once
         expected: conf=ok/ok/ok/ok profile=ok/ok/ok/ok
         actual:   conf=ok/ok/ok/ok profile=BAD/BAD/BAD/BAD
    FAIL comparison 3 - both counters use 'git ls-files --cached --others --exclude-standard'
         expected: conf=ok/ok/ok profile=ok/ok/ok
         actual:   conf=ok/ok/ok profile=BAD/BAD/BAD

profile-counters: 24 passed, 16 failed
```

Note `conf=ok/ok/ok/ok` in all three comparisons: the side this story must **not**
change is already right, and the guard says so.

### The whole self-test, and the shape of `gates.sh --fast`

`bash scripts/selftest.sh` — 18 suites, and **only the new one is red**. No other
suite objects to the new file, including the five that read `.claude/tests/*`
(`lib`'s portability scans, `ci-local`, `harness-gate`, `refresh`, `settings`):

    === profile-counters ===
    profile-counters: 24 passed, 16 failed
    ...
    1 of 18 harness suite(s) FAILED.

`bash scripts/gates.sh --fast`:

    --- gate summary ---
    PASS         format (0s, observed 43)
    PASS         lint (0s, observed 43, floor 1)
    PASS         typecheck (2s, observed 8)
    PASS         unit (21s, observed 197, floor 197)
    UNCONFIGURED coverage
    PASS         build (0s, observed 25103)
    PASS         harness (21s, observed 40)
    All required gates passed (6 ran, 1 unconfigured, 0 known).

**`--fast` green in RED is the correct shape *for this story*, and only for this
story.** Normally a green fast run at the end of RED means the tests are not
admissible; here no gate reads a markdown reference, the guard is named by no
`gate` line, and `## Contract` (a) priced that in explicitly. What the run does
tell me is the thing it is for: lint, types and build are unaffected, the new file
trips no tooling, and the `harness` gate still passes 40/40 — so nothing I wrote
has made the existing gates unable to judge the story. The red lives in
`selftest.sh`, which is what CI's required `gates` job runs first.

### The shape GREEN must produce

There is no module and nothing is exported — the artifact is markdown. The
equivalent contract is the **shape of the text**, and the suite already pins it,
so a wrong guess is a red assertion rather than a debate. Stated as fact:

**Scope: every line in the profile whose first pipe-field is `gate`.** Today that
is seven lines, and **two of them are `lint`** — line 40 (the "verified form"
example in *The shape of the problem*) and line 78 (the gate table). Both are
prescriptions. Either correct both, or turn line 40 into prose (inline backticks
in a paragraph, as line 44 already does). **Do not write a deliberately-wrong
`gate | ... |` line as a counter-example**: the suite cannot tell it from a
prescription, and it will be reported.

For every `gate | format | ... | <cmd>`, `<cmd>` must:

| Requirement | Exact test |
|---|---|
| count from stylua's own output | contains the literal `debug: formatted ` (**with the trailing space**) |
| carry its own exit status | contains the literal `PIPESTATUS[0]` |
| not enumerate beside the tool | contains **none** of `git ls-files`, `COUNT(`, `find ` (trailing space), `wc -l` |

For every `gate | lint | ... | <cmd>`:

| Requirement | Exact test |
|---|---|
| one target assignment | `${GATE_LINT_TARGET:=` occurs **exactly once** |
| the counter reads it | the bare token `GATE_LINT_TARGET` occurs **≥ 2** times |
| the path list once | the text between `${GATE_LINT_TARGET:=` and the next `}` occurs **exactly once** in the whole command |
| the pathspec | `git ls-files --cached --others --exclude-standard` occurs **≥ 1** time, and as many times as `git ls-files` occurs at all |
| no `find` | no `find ` |

For every `gate | typecheck | ... | <cmd>`: identical, with `GATE_TYPE_TARGET`.

Copying `project.conf`'s three commands verbatim satisfies every row — that is
what assertion 39 proves, by building exactly that document and finding it clean.

Prose, asserted as **claims** with alternatives (any one per group; all tokens of
a claim within the stated window of consecutive lines):

| Claim | AC | Accepted vocabulary (any one) | Window |
|---|---|---|---|
| the defect instruction is gone | AC-4 | the string `count its own inputs` must not appear **anywhere** | — |
| prefer the tool's own count | AC-4 | `tool's own` / `'s own count` / `'s own output` / `prefer the tool` / `read the count out of the tool` / `the tool already counts` | 4 lines |
| derive only where the tool has none | AC-4 | `derive`/`derived`/`deriving`/`derivation` **and** one of `has none`, `has no count`, `no count of its own`, `no per-file`, `does not print`, `prints no`, `emits none` | 6 lines |
| hazard 1, the `**/` pathspec | AC-5 | `**/*.luau` **and** `ls-files` **and** one of `one or more directories`, `never zero`, `never matches zero` | 8 lines |
| hazard 2, index not disk | AC-5 | `[ -e "$f" ]` **and** one of `index, not the disk`, `index rather than the disk`, `reads the index`, `the index and not the disk` | 8 lines |
| hazard 3, pipefail on empty | AC-5 | `pipefail` **and** one of `empty tree`/`an empty target`/`empty target` **and** one of `exit 0`/`exits 1`/`exit 1` | 8 lines |
| hazard 4, doctor.sh's first token | AC-5 | `doctor.sh` **and** one of `first token`, `first word` | 8 lines |
| the Verified banner | EPIC-00 | all ten of `Verified 2026-09-15`, `Rokit 1.2.0`, `Rojo 7.7.0`, `Wally 0.3.2`, `Lune 0.10.5`, `Selene 0.31.0`, `StyLua 2.5.2`, `luau-lsp 1.69.0`, `Linux verified 2026-09-16`, `macOS is still unverified`; five of them within 10 lines of each other | 10 lines |
| the Rokit install line | EPIC-00 | one line carrying `curl`, `rokit` and `install.sh`, **below** a `## Prerequisites` heading | 1 line |

Matching is **literal and case-insensitive** throughout (`index()`, not a regex),
so backticks, bold markers and punctuation around a token are all fine.

**Not constrained, and deliberately GREEN's choice:** wording outside the
vocabularies above, section order, heading text, the gate table's column padding,
whether the `COUNT(dirs)` macro survives as documentation, the `<dirs>` placeholder
convention, comment style, and anything about `unit`, `coverage` or `build`. There
is **no byte comparison** with `project.conf` anywhere.

**One thing GREEN must not do**: `## Contract` is explicit that
`.claude/harness/project.conf` does not change, and assertions 26-29 will go red if
it does. If you believe the conf is wrong, that is a finding to raise, not a fix.

### Mutation table — MEASURED, all 13 run today against the shipped suite

Baseline is 24 passed / 16 failed. "Newly red" is the set difference against that
baseline, computed per run. Command form:

    bash scripts/mutate.sh <FILE> '<EXPR>' -- bash .claude/tests/profile-counters.test.sh

| # | File | Expression | Newly red | n |
|---|---|---|---|---|
| M1 | profile | `s/Selene 0.31.0/Selene 9.9.9/` | the `Verified` banner still names all seven pinned tools | **1** |
| M2 | profile | `s\|rokit/main/scripts/install.sh\|rokit/main/scripts/setup.sh\|` | the Rokit curl install line survives under Prerequisites | **1** |
| M3 | profile | `s/gate \| format    \| optional/gate \| formatX   \| optional/` | the profile prescribes a format, a lint and a typecheck gate command | **1** (and **3 AC-1 assertions go GREEN** — the vacuity this precondition exists to catch, demonstrated) |
| M4 | profile | `s/one or more directories, never zero/exactly what you expect/` | hazard 1; + the corrected-document hazard check | 2 |
| M5 | profile | `s/index, not the disk/working tree/` | hazard 2; + same | 2 |
| M6 | profile | `s/empty tree/full tree/g` | hazard 3; + same | 2 |
| M7 | profile | `s/first token/FIRST-TOKEN-CLAIM-DELETED/` | hazard 4; + same | 2 |
| M8 | profile | `s/Linux verified 2026-09-16/Linux checked at some point/` | banner token list; banner cohesion | 2 |
| M9 | conf | `s/debug: formatted /debug: FORMATTED /` | conf format anchor; + "corrected profile is clean" | 2 |
| M10 | conf | `s/PIPESTATUS\[0\]/PIPESTATUS[9]/` | conf format status; + same | 2 |
| M11 | conf | `s/--cached --others --exclude-standard/--cached/` | conf counter pathspec; + same | 2 |
| M12 | conf | `s/\${GATE_LINT_TARGET:=src tests lune}/src tests lune/` | conf single-target naming; + same | 2 |
| M13 | conf | `s/gate \| format    \| optional/gate \| formatX   \| optional/` | conf precondition; + same | 2 |

**M1, M2 and M3 are the single-assertion entries** — verify those first. The
"+ corrected-document" second hit in M9-M13 is not noise: assertion 39 builds its
fixture *from* `project.conf`, so a conf regression correctly lands there too.

### Mutation table — PREDICTED, for the rewritten profile (`## Notes` 1-3)

Not run, because the profile is not rewritten yet; each prediction names what
grounds it.

| # | Expression on the REWRITTEN profile | Predicted newly red | n | Grounded by |
|---|---|---|---|---|
| P1 | `s/-- \$GATE_LINT_TARGET/-- src tests lune/` | *every lint gate command names the target path list exactly once* — "the target list 'src tests lune' is named 2 times, want exactly 1" | **1** | assertions 35-37, which run this exact shape against `REGRESSED_FIXTURE` today and pass |
| P2 | `## Notes` 1 as written — restore `COUNT(src tests lune)` in the lint line | assertions 8, 9, 14, 31, 32 | 5 | assertions 33-34, which run that exact shape against `DIRTY_FIXTURE` today |
| P3 | `s/--cached --others --exclude-standard/--/` | assertions 12, 14, 15, 32 | 4 | M11's measured behaviour on the conf side |
| P4 | delete any one hazard | that hazard's assertion (19-22) **naming it**, + assertion 40 | 2 | M4-M7, measured |

**Prefer P1 over P2** when checking that AC-2 discriminates: it is the regression
AC-7 is actually aimed at — a second enumeration added back to a command that
already looks right — and it isolates to one assertion.

### Assertions green on arrival, and what earns each

All 24. The artifact exists and is only *partly* wrong, so this is expected and the
story's `## Deferred verifications` predicted it. **There are no deferred
verifications and nothing is a claim**: unlike an ordinary RED, this suite does not
fail at import — every assertion in it executed on every run, controls included, so
the numbers in the mutation table are *measured*, not expected. Full output in
`## Regressions`.

| Assertion(s) | Earned by |
|---|---|
| 1-2 (files exist) | the branch above them `exit 1`s; no separate probe |
| 3 (profile has the three gates) | **M3**, measured |
| 4 (conf has the three gates) | **M13**, measured |
| 13 (no `find` in a gate command) | shares `scan_gates` with assertion 12, which is red today on line 40; vacuous on its own until a `find` appears |
| 19-22 (four hazards) | **M4-M7**, one mutation each, each naming its own hazard |
| 23-25 (EPIC-00) | **M1, M8, M2** |
| 26-29 (conf's three shapes) | **M9-M12** |
| 33-37 (AC-7 naming) | these are the suite's **negative controls**, not probed assertions: they feed the same checker functions a deliberately defective prescription and require it to report. Non-vacuous by two independent facts — the same functions produce all 16 red assertions above against the real profile, and the paired clean fixture (38) stays green |
| 38 (prose is not a prescription) | its positive control is 33-37: the same scanner, the same document shape, one defective gate line, reported |
| 39 (corrected profile is clean) | **M9-M13**, each of which takes it red |
| 40 (corrected profile still states the hazards) | **M4-M7**, each of which takes it red |

### What changed my approach, and what GREEN should know

1. **A probe caught two needles that their own mutation satisfied.** `matches zero`
   and `first argument of each gate` were accepted phrasings for hazards 1 and 4,
   and both are satisfied by a sentence meaning the *opposite*. The hazard-4 probe
   left the suite green. Both alternations are now narrower. This is why hazard
   assertions are probed individually rather than as a block.
2. **The sharpest AC-2 check was initially unexercised.** On today's profile the
   "names the target N times" arm is never reached — with no `${GATE_LINT_TARGET:=}`
   there is no list to count, so the check reports the missing assignment and
   stops. Without `REGRESSED_FIXTURE` that arm would have shipped never having run.
3. **`gates.sh --fast` cannot see this guard**, so GREEN must run
   `bash scripts/selftest.sh profile-counters` explicitly. `--fast` staying green
   says nothing about this story.
4. **Every claim in the RED brief was checked and every one held**:
   `selftest.sh:20` globs `.claude/tests/*.test.sh`; `gates.yml:107` runs it in the
   required `gates` job; `project-counters.test.sh:36-42` hard-fails on a missing
   tool; upstream ships neither `profile-counters.test.sh` nor
   `project-counters.test.sh`; line 51 is a bare `git ls-files` inside the hazard
   sentence; `mutate.sh` ran 13 times in RED and verified every restore.

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

**This story has not returned to RED.** The section is here because
`## Deferred verifications` directs it here: the artifact already exists, so 24 of
the suite's 40 assertions pass on their first execution and are unearned until a
mutation of the specific text each one pins takes it red. Thirteen mutations, all
through `scripts/mutate.sh`, all restored and verified with `cmp`. Baseline before
every one of them:

    $ bash .claude/tests/profile-counters.test.sh
    profile-counters: 24 passed, 16 failed

"NEWLY RED" below is the set difference of the FAIL lines against that baseline,
computed per run. Every one of these was re-run **after** the fork-count refactor,
so the evidence is against the suite as shipped.

```
########## AC-5 hazard 1
$ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md 's/one or more directories, never zero/exactly what you expect/' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 22 passed, 18 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_skills_stack-profiles_reference_roblox-luau.md.20260917T173137Z.3690319.bak) ===
NEWLY RED:
    FAIL and that same corrected document still states all four hazards
    FAIL hazard 1: a git pathspec's '**/' never matches zero directories
NEWLY GREEN:
########## AC-5 hazard 2
$ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md 's/index, not the disk/working tree/' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 22 passed, 18 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_skills_stack-profiles_reference_roblox-luau.md.20260917T173145Z.3690854.bak) ===
NEWLY RED:
    FAIL and that same corrected document still states all four hazards
    FAIL hazard 2: git ls-files reads the index, not the disk (hence [ -e "$f" ])
NEWLY GREEN:
########## AC-5 hazard 3
$ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md 's/empty tree/full tree/g' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 22 passed, 18 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_skills_stack-profiles_reference_roblox-luau.md.20260917T173152Z.3691269.bak) ===
NEWLY RED:
    FAIL and that same corrected document still states all four hazards
    FAIL hazard 3: a grep stage exits 1 on an empty tree and takes the && chain with it under pipefail
NEWLY GREEN:
########## AC-5 hazard 4
$ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md 's/first token/FIRST-TOKEN-CLAIM-DELETED/' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 22 passed, 18 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_skills_stack-profiles_reference_roblox-luau.md.20260917T173200Z.3691635.bak) ===
NEWLY RED:
    FAIL and that same corrected document still states all four hazards
    FAIL hazard 4: doctor.sh reads the FIRST TOKEN of a gate command as the executable
NEWLY GREEN:
########## EPIC-00 banner versions
$ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md 's/Selene 0.31.0/Selene 9.9.9/' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 23 passed, 17 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_skills_stack-profiles_reference_roblox-luau.md.20260917T173208Z.3691993.bak) ===
NEWLY RED:
    FAIL the Verified banner still names all seven pinned tools and both platform verdicts
NEWLY GREEN:
########## EPIC-00 banner cohesion
$ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md 's/Linux verified 2026-09-16/Linux checked at some point/' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 22 passed, 18 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_skills_stack-profiles_reference_roblox-luau.md.20260917T173216Z.3692370.bak) ===
NEWLY RED:
    FAIL ... and they are one banner, not scattered across the document
    FAIL the Verified banner still names all seven pinned tools and both platform verdicts
NEWLY GREEN:
########## EPIC-00 Rokit curl line
$ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md 's|rokit/main/scripts/install.sh|rokit/main/scripts/setup.sh|' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 23 passed, 17 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_skills_stack-profiles_reference_roblox-luau.md.20260917T173224Z.3692725.bak) ===
NEWLY RED:
    FAIL the Rokit curl install line survives under Prerequisites
NEWLY GREEN:
########## conf format anchor
$ bash scripts/mutate.sh .claude/harness/project.conf 's/debug: formatted /debug: FORMATTED /' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 22 passed, 18 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260917T173232Z.3693154.bak) ===
NEWLY RED:
    FAIL conf: the format gate counts from stylua's own output
    FAIL today's profile with only its gate lines corrected is clean, hazard paragraphs and all
NEWLY GREEN:
########## conf format status
$ bash scripts/mutate.sh .claude/harness/project.conf 's/PIPESTATUS\[0\]/PIPESTATUS[9]/' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 22 passed, 18 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260917T173240Z.3693674.bak) ===
NEWLY RED:
    FAIL conf: the format gate takes its status from ${PIPESTATUS[0]}
    FAIL today's profile with only its gate lines corrected is clean, hazard paragraphs and all
NEWLY GREEN:
########## conf counter pathspec
$ bash scripts/mutate.sh .claude/harness/project.conf 's/--cached --others --exclude-standard/--cached/' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 22 passed, 18 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260917T173249Z.3694209.bak) ===
NEWLY RED:
    FAIL conf: both counters use --cached --others --exclude-standard
    FAIL today's profile with only its gate lines corrected is clean, hazard paragraphs and all
NEWLY GREEN:
########## conf single-target naming
$ bash scripts/mutate.sh .claude/harness/project.conf 's/\${GATE_LINT_TARGET:=src tests lune}/src tests lune/' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 22 passed, 18 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260917T173258Z.3694749.bak) ===
NEWLY RED:
    FAIL conf: lint and typecheck name their target once, through ${GATE_*_TARGET:=...}
    FAIL today's profile with only its gate lines corrected is clean, hazard paragraphs and all
NEWLY GREEN:
########## precondition: profile has a format prescription
$ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md 's/gate | format    | optional/gate | formatX   | optional/' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 26 passed, 14 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_skills_stack-profiles_reference_roblox-luau.md.20260917T173309Z.3695278.bak) ===
NEWLY RED:
    FAIL the profile prescribes a format, a lint and a typecheck gate command
NEWLY GREEN:
    FAIL every format gate command counts stylua's own 'debug: formatted' lines
    FAIL every format gate command takes its status from ${PIPESTATUS[0]}
    FAIL no format gate command enumerates its inputs beside the tool
########## precondition: conf has a format prescription
$ bash scripts/mutate.sh .claude/harness/project.conf 's/gate | format    | optional/gate | formatX   | optional/' -- bash .claude/tests/profile-counters.test.sh
profile-counters: 22 passed, 18 failed
=== mutate: command exited 1; restored (verified byte-for-byte against /c/Users/ryanc/Projects/first-roblox/.claude/state/mutations/.claude_harness_project.conf.20260917T173319Z.3695788.bak) ===
NEWLY RED:
    FAIL project.conf prescribes the same three
    FAIL today's profile with only its gate lines corrected is clean, hazard paragraphs and all
NEWLY GREEN:
```

**Read the last-but-one block twice.** Renaming the profile's `format`
prescription takes the precondition red and **three AC-1 assertions green** — a
scan over zero matching lines is silently clean. That is the vacuity the
precondition exists to catch, demonstrated rather than asserted, and it is why
`verdict()` has a `no-gate` arm.

### A defective needle this found, before the profile was ever rewritten

The hazard-4 probe originally read `s/first token/first argument/` and left the
suite **green**:

    === mutate: .claude/skills/stack-profiles/reference/roblox-luau.md (1 line(s) changed by s/first token/first argument/) ===
    profile-counters: 24 passed, 16 failed
    === mutate: command exited 1; restored (verified byte-for-byte ...) ===

Cause: `first argument of each gate` was one of the accepted phrasings, so the
mutation rewrote the sentence into a string the assertion already admitted — and
"the first *argument*" is not even the claim (`doctor.sh` reads the first
**token**, which is the executable). `matches zero` in hazard 1 had the same
defect from the other direction: it is satisfied by a sentence saying `**/`
*matches zero directories*, the opposite of the hazard. Both alternatives were
removed and the probe re-run; it is M7 in the table above and is red.

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

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-17T19:34:59Z
    commit: d635f94
    tree:   7dd91365d27ad2d22361372720a82fa17e7d788f
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 43)
    PASS         lint (0s, observed 43, floor 1)
    PASS         typecheck (3s, observed 8)
    PASS         unit (29s, observed 197, floor 197)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (0s, observed 25103)
    PASS         harness (21s, observed 40)
    UNCONFIGURED mutation

## Gate probes

<!-- REQUIRED if this story adds or changes a gate, its command, or its
     evidence line. Omit the section entirely otherwise.
     A gate that has never been observed to fail is not a gate: break the thing
     it guards, run the gate, paste the failure, revert. One block per gate:
       * what was broken, and where
       * the gate output proving it failed
       * confirmation the probe was reverted -->

## Notes

**Mutations the orchestrator should run at acceptance**, via
`bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md '<expr>' -- bash .claude/tests/<suite>`:

1. **Restore `COUNT(src tests lune)` in the `lint` line.** Predicted: AC-2's guard
   goes red and names the line. Run this one first — it is the defect the story
   exists for.
2. **Revert the pathspec to bare `git ls-files`.** Predicted: AC-3 goes red.
3. **Delete one of the four documented hazards.** Predicted: AC-5 goes red naming
   that hazard. If it stays green, AC-5 was written as "the prose is long enough".

**Do not let the guard assert wording.** The most likely way this story ships
something worthless is an AC-4 or AC-5 check that greps for a sentence, which
turns every honest future edit into a failing test and gets deleted within two
stories.

**Where this came from.** `HARNESS-006`'s `## Out of scope`, and its PR: *"the
same defective shape still ships in the profile every project generated from it
inherits."* Confirmed at filing time — `roblox-luau.md:40` and the `COUNT(dirs)`
macro at line ~75.

### GREEN's confirmation of the controls (2026-09-17)

Not in `## Gate probes`: this story adds and changes no gate, and
`check-boundaries.sh` reads that section as a claim about one.

    $ bash .claude/tests/profile-counters.test.sh      # and via scripts/selftest.sh profile-counters
    profile-counters: 40 passed, 0 failed

**P1 was run against the rewritten profile, and its prediction was wrong in
count — 3 newly red, not 1.** The predicted assertion did fire, verbatim and
naming both lint prescriptions; two more fired with it. Both extras are genuine,
so this is a divergence in the prediction rather than a defect in the suite or
the rewrite:

    $ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md \
        's/-- \$GATE_LINT_TARGET/-- src tests lune/' -- bash .claude/tests/profile-counters.test.sh
        FAIL every lint gate command names its target through a single ${GATE_LINT_TARGET:=...} the counter reads
             line 75:  '${GATE_LINT_TARGET:=...}' is assigned but $GATE_LINT_TARGET is never read back, so the counter is not sharing the tool's target
             line 135: '${GATE_LINT_TARGET:=...}' is assigned but $GATE_LINT_TARGET is never read back, so the counter is not sharing the tool's target
        FAIL every lint gate command names the target path list exactly once
             line 75:  the target list 'src tests lune' is named 2 times, want exactly 1 - a second enumeration is the HARNESS-006 defect
             line 135: the target list 'src tests lune' is named 2 times, want exactly 1 - a second enumeration is the HARNESS-006 defect
        FAIL comparison 2 - lint/typecheck: both name the target through a single ${GATE_*_TARGET:=...}, path list once
             expected: conf=ok/ok/ok/ok profile=ok/ok/ok/ok
             actual:   conf=ok/ok/ok/ok profile=BAD/BAD/ok/ok
    profile-counters: 37 passed, 3 failed
    === mutate: command exited 1; restored (verified byte-for-byte against
        .../roblox-luau.md.20260917T190327Z.3943629.bak) ===

**Why the handoff predicted 1.** It grounded P1 on assertions 35-37, which feed
`REGRESSED_FIXTURE` — the same mutated shape — through **four scans concatenated
into one string** and then `assert_contains` on it. The fixture therefore cannot
distinguish which of the four checks produced a message, so the read-back arm of
`_ck_target_named_once` was firing there all along, invisibly. Against a real
document each check is its own assertion, so the same mutation surfaces three.
The third (AC-6 comparison 2) aggregates the first two and follows from them.

**This is a net gain in evidence.** The "assigned but never read back" arm had
never been observed to fail: it is in none of RED's 16 failures (today's profile
has no `${GATE_LINT_TARGET:=}` at all, so the *earlier* arm reports and returns)
and no mutation in the measured table reached it. P1 has now reached it, on the
shipped suite, against the shipped profile.

**P4, twice, because GREEN rewrote two of the four hazard bullets** (hazard 3
gained the `grep -c` finding, hazard 4 the `T="..."; tool $T` finding). Both
needles still bite on the new wording, 2 newly red each, exactly as predicted:

    $ bash scripts/mutate.sh ... 's/first token/FIRST-TOKEN-CLAIM-DELETED/' -- ...
        FAIL hazard 4: doctor.sh reads the FIRST TOKEN of a gate command as the executable
        FAIL and that same corrected document still states all four hazards
    profile-counters: 38 passed, 2 failed

    $ bash scripts/mutate.sh ... 's/empty tree/full tree/g' -- ...
        FAIL hazard 3: a grep stage exits 1 on an empty tree and takes the && chain with it under pipefail
        FAIL and that same corrected document still states all four hazards
    profile-counters: 38 passed, 2 failed

All three restores verified byte-for-byte by `mutate.sh`; no `.bak` remains under
`.claude/state/mutations/`, and `40 passed, 0 failed` was re-confirmed afterwards.

**Two claims in the GREEN dispatch were checked and held.** `stylua --check -v`
does print one `debug: formatted ` line per file it read — measured here, 43,
which is the same number the `format` gate reports as `observed 43`. And no
`gate` line names this suite, so `gates.sh --fast` cannot run it; it was run by
hand, both directly and through `scripts/selftest.sh profile-counters`.

**`gates.sh --fast` after the rewrite** — unchanged from RED, which is the only
thing it can tell this story: `format 43`, `lint 43`, `typecheck 8`,
`unit 197`, `build 25103`, `harness 40`, all required gates passed. Not
recorded, because a partial run is not a record. The full run belongs to GATES.

---

## PO decisions, taken at PLANNED (2026-09-17)

Recorded here rather than in `## Notes` above so the mutation list stays a
mutation list. Every one is a fact checked against the tree today, with the
command that checked it.

**1. `required_gates` stays empty — and the reason has changed since filing.**
The story's `## Context` says no gate reads a markdown reference. Still true, but
incomplete: `HARNESS-008` has since added a **required** `harness` gate. The
reason `required_gates` stays empty is now the narrower one in `## Contract` (a):
the guard goes in a new toolchain-free suite, which `selftest.sh` discovers and
CI's required `gates` job runs, and which no `gate` line names.

Separately, the mechanism that would have forced the issue cannot fire here at
all. `gates.sh` matches `covers` lines against a story's changed **source** paths
only, and every path this story writes classifies `harness`:

    $ bash scripts/classify.sh .claude/skills/stack-profiles/reference/roblox-luau.md \
                               .claude/tests/project-counters.test.sh \
                               .claude/tests/profile-counters.test.sh
    harness  .claude/skills/stack-profiles/reference/roblox-luau.md
    harness  .claude/tests/project-counters.test.sh
    harness  .claude/tests/profile-counters.test.sh

So `gates.sh` will neither FAIL nor WARN on coverage for this story. That is not
the same as the artifact being guarded, which is what AC-7 is for.

**2. The guard is a new file, not an extension of `project-counters.test.sh`.**
The `## Contract` (a) table has the reasoning; the deciding fact is that
`project-counters.test.sh` requires the Roblox toolchain and treats a missing tool
as a hard failure, by its own header:

    $ sed -n '36,43p' .claude/tests/project-counters.test.sh
    # REQUIRES THE TOOLCHAIN. Unlike every other suite in .claude/tests this one
    # shells out to stylua, selene, rojo and luau-lsp, ...
    # A missing tool is a hard failure and never a skip ...

RED still names the file and still writes the reasoning in `## Test plan`.
**Reported to the user before dispatch**, because it narrows a choice the
contract had delegated.

**3. `EPIC-00` is DONE and two of its done-when rows cite text inside the file
GREEN rewrites.** See `## Contract` (d). This is the "check the epic's done-when"
step, arriving from the other direction than usual: the risk is not that this
story leaves an epic's promise undelivered, but that its rewrite silently
**un**-delivers one that is already closed. Closed by adding it to the contract as
a GREEN obligation and an AC-5-shaped RED assertion. **Reported to the user before
dispatch.**

    $ grep -n 'roblox-luau' docs/backlog/epics/EPIC-00.md
    46:  `.claude/skills/stack-profiles/reference/roblox-luau.md` have their
    90:| ... both carry a `Verified 2026-09-15` banner naming Rokit 1.2.0, ...
    108:(`roblox-luau.md`, Prerequisites). Linux is now verified, ...

**4. RED runs on `opus`, overriding `plan.sh`'s printed `fable` — and `plan.sh`
is wrong here for a reason worth reporting upstream.** `models.conf` carries
`except | RED | unenforced | opus`: *"the lock freezes none of the paths this
story names, so the contract is not an aid to the model here - it is the only
enforcement there is."* That describes this story exactly, and `## Contract`
("The phase lock enforces nothing here either") already says so.

`plan.sh` printed `fable` anyway. `contract_unenforced()`
(`scripts/plan.sh:96`) extracts path-like tokens from `## Contract` with a bare
regex and requires **all** of them to classify harness/docs/ignored. It cannot
tell a path the story *writes* from a path the story *mentions*, so the
`ls ../agentic-dev-harness/...` listings, the `classify.sh src/app/main.ts`-style
illustrations and the bare basenames in the ownership table all count:

    harness  .claude/skills/stack-profiles/reference/roblox-luau.md   <- a path we write
    source   check-boundaries.sh                                       <- prose, basename only
    source   src/shared/x.luau                                         <- an illustration
    source   agentic-dev-harness/.claude                               <- half of an `ls` line

Three of those four are not paths this story touches, and any one of them flips
the verdict. The override is therefore a correction of the heuristic, not a
departure from the policy — the policy row fires; the detector missed it.

**This is a defect in `scripts/plan.sh`, not in this story, and it is not fixed
here.** `plan.sh` is upstream's (`ls ../agentic-dev-harness/scripts/plan.sh`), so
a local patch is destroyed by the next `refresh-harness.sh` — the same trap
`## Out of scope` already documents for `new-profile.md` and `profiles.test.sh`.
It belongs in a change to `../agentic-dev-harness`. Filed as a finding to raise,
not as work to absorb; the note is here so the next reader of this story does not
re-derive it. Worth noting the failure mode is **safe in this direction** — it
resolves *up* to the stronger model — but it is a coin flip on prose, and a story
whose prose happened to mention only harness paths would resolve *down* on the
same non-reasoning.

---

## Orchestrator verification of RED (2026-09-17)

Every number below is from a command run by the Lead PO, not from the
test-developer's report. A report of success is a claim.

**The suite fails, and for the right reason.**

    $ bash .claude/tests/profile-counters.test.sh
    profile-counters: 24 passed, 16 failed        (11.9 s, exit 1)

All 16 name a profile line number and quote the line. None is a syntax error, a
missing file or an import failure. Spot-checked the AC-2 arm against the two
`gate | lint` lines the profile carries (40 and 78) — both reported.

**Only two files changed.** `git status --porcelain` shows exactly
` M docs/backlog/stories/HARNESS-007.md` and
`?? .claude/tests/profile-counters.test.sh`. The profile and `project.conf` are
byte-untouched after 15 `mutate.sh` runs (13 RED's, 2 mine); no `.bak` remains
under `.claude/state/mutations/`, so every restore verified.

**Admissibility — `bash scripts/gates.sh --fast`, exit 0:**

    PASS  format    (1s,  observed 43)
    PASS  lint      (1s,  observed 43, floor 1)
    PASS  typecheck (4s,  observed 8)
    PASS  unit      (23s, observed 197, floor 197)
    PASS  build     (1s,  observed 25103)
    PASS  harness   (35s, observed 40)
    All required gates passed (6 ran, 1 unconfigured, 0 known).

Identical counts to RED's run. The new file trips no lint, type or format rule,
so the tests are admissible. `harness`'s `observed 40` is the independent
confirmation that `project-counters.test.sh` still passes 40/40 with the new file
present. **`--fast` green at the end of RED is correct only because of
`## Contract` (a)** — no gate reads a markdown reference and no `gate` line names
this suite. The red lives in `selftest.sh`, which CI's required `gates` job runs
first. RED flagged this rather than presenting it as a clean bill of health.

**No other suite objects to the new file.** Twelve suites completed in a full
`scripts/selftest.sh` run before it was stopped (see the note below), all 0
failed: `boundaries` 73, `ci-local` 28, `classify` 27, `doctor` 27,
`gate-reminder` 27, `gates` 74, `harness-gate` 29, `lib` 136, `mutate` 39,
`new-story` 22, `phase-guard` 178, `phase` 33. The three remaining suites that
read `.claude/tests/*` or `reference/*` were then run individually:

    refresh:  51 passed, 0 failed
    settings: 20 passed, 0 failed
    profiles: 44 passed, 0 failed

`project-counters` is covered by the `harness` gate above. That is all five suites
RED identified as reading `.claude/tests/*`, plus `profiles`, green.

### The two mutations, run by the orchestrator

Not re-runs of RED's probes — one verifies its table, one closes a hole RED
disclosed. Baseline for both: 24 passed, 16 failed.

**1. M1 from the handoff table, chosen because it predicts a SINGLE assertion.**

    $ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md \
        's/Selene 0.31.0/Selene 9.9.9/' -- bash .claude/tests/profile-counters.test.sh
    ...
        FAIL the Verified banner still names all seven pinned tools and both platform verdicts
    profile-counters: 23 passed, 17 failed
    === mutate: command exited 1; restored (verified byte-for-byte against
        .../roblox-luau.md.20260917T185048Z.3908324.bak) ===

Predicted 1 newly red, measured 1 newly red, and it is the named assertion. The
mutation table is evidence rather than a claim.

**2. The `find` control, which RED disclosed it could not exercise.** Assertion 13
(`ck_no_find`) was **vacuous**: nothing in today's profile enumerates with `find`,
so it had never been observed to fail — while AC-3 names it as an explicit control
("`find` must also fail it"). RED said so in `## Test plan` rather than letting it
pass quietly, which is the right call, but it left the one assertion in the suite
that no evidence covered. Closed here by putting a `find` pipeline into a real
gate command:

    $ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md \
        's#COUNT(src tests lune)#n=$(find src tests lune -name "*.luau" | wc -l)#' \
        -- bash .claude/tests/profile-counters.test.sh
    === mutate: ... (2 line(s) changed ...) ===
    ...
        FAIL no gate command in the profile enumerates with 'find'
             actual:   line 77: enumerates with 'find', which sweeps in gitignored build output - HARNESS-006 measured 39 against the tools' 38
             line 78: enumerates with 'find', which sweeps in gitignored build output - HARNESS-006 measured 39 against the tools' 38
    profile-counters: 23 passed, 17 failed
    === mutate: command exited 1; restored (verified byte-for-byte against
        .../roblox-luau.md.20260917T185121Z.3910077.bak) ===

Exactly one newly red, naming **both** offending lines. Every assertion in the
suite has now been observed to fail.

Baseline confirmed restored afterwards: `profile-counters: 24 passed, 16 failed`.

### Two things carried forward, neither in this story's scope

**`scripts/selftest.sh` is impractical as a local loop on this machine**, and that
matters because it is the *only* thing that runs this story's guard. The full run
was stopped after 20 minutes, inside `plan.test.sh`, which re-invokes `plan.sh`;
a single `bash scripts/plan.sh HARNESS-007` took ~110 s here, and
`bash scripts/gates.sh --list` over two minutes. `phase-guard` took ~5 minutes for
178 assertions. All of it is fork cost — the same ~30 ms/fork Windows penalty RED
measured and engineered out of its own suite (30.5 s → 9.6 s). CI reports the
whole `gates` job at 54 s on `ubuntu-24.04` (`EPIC-00`, done-when row 4), so this
is a local-platform cost and not a regression. **`plan.test.sh` is therefore the
one suite not verified locally on this branch**; it reads fixtures, not this
story's artifact, and CI runs it.

**`scripts/plan.sh`'s `contract_unenforced()` is defective** — PO decision 4 above
has the analysis. Upstream's file; report it to `../agentic-dev-harness` rather
than patch it here.

### Orchestrator verification of GREEN (2026-09-17)

Run by the Lead PO, not read out of GREEN's report.

**The freeze held, and it was unenforced.** `bash scripts/classify.sh` says both
`.claude/tests/profile-counters.test.sh` and the profile classify `harness`, which
GREEN may write — so the phase lock could not have stopped an edit to the suite.
Checked directly:

    $ git diff -- .claude/tests/profile-counters.test.sh .claude/harness/project.conf
    (no output)

    $ git status --porcelain
     M .claude/skills/stack-profiles/reference/roblox-luau.md
     M docs/backlog/stories/HARNESS-007.md

Tests frozen, `project.conf` untouched, exactly the two files the contract allows.

**The suite passes and the gates are unmoved.**

    $ bash .claude/tests/profile-counters.test.sh
    profile-counters: 40 passed, 0 failed

    $ bash scripts/gates.sh --fast        # exit 0
    PASS format (43) · lint (43, floor 1) · typecheck (8) · unit (197, floor 197)
    PASS build (25103) · harness (40)
    All required gates passed (6 ran, 1 unconfigured, 0 known).

**EPIC-00's evidence survived, byte-for-byte.** Contract (d)'s two obligations,
checked as a property of the diff rather than of the assertions that pin them:

    $ git diff -- .../roblox-luau.md | grep -E '^[-+].*(Verified 2026-09-15|Rokit 1\.2\.0|Linux verified|macOS is still|install\.sh)'
    (no output)

Neither the banner nor the Rokit `curl` line appears on either side of the diff,
so neither was touched.

**P1's correction, reproduced independently.** GREEN reported that a mechanism the
Lead PO's own dispatch named — "P1 isolates to one assertion" — does not hold. Re-run
here, on a different invocation, against the shipped suite:

    $ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md \
        's/-- \$GATE_LINT_TARGET/-- src tests lune/' -- bash .claude/tests/profile-counters.test.sh
        FAIL every lint gate command names its target through a single ${GATE_LINT_TARGET:=...} the counter reads
             line 75:  '${GATE_LINT_TARGET:=...}' is assigned but $GATE_LINT_TARGET is never read back, ...
             line 135: '${GATE_LINT_TARGET:=...}' is assigned but $GATE_LINT_TARGET is never read back, ...
        FAIL every lint gate command names the target path list exactly once
             line 75:  the target list 'src tests lune' is named 2 times, want exactly 1 ...
             line 135: the target list 'src tests lune' is named 2 times, want exactly 1 ...
        FAIL comparison 2 - lint/typecheck: ...
             actual:   conf=ok/ok/ok/ok profile=BAD/BAD/ok/ok
    profile-counters: 37 passed, 3 failed
    === mutate: ... restored (verified byte-for-byte against
        .../roblox-luau.md.20260917T191420Z.3980801.bak) ===

**37/3 confirmed. GREEN's count is right and the dispatch's was wrong.** The
diagnosis was also checked against the code rather than taken on trust:
`REGRESSED_OFF` in the suite is four `scan_gates` calls concatenated into one
string with `assert_contains` over it, so assertions 35-37 genuinely cannot
attribute a message to a check. The prediction under-counted **detection**; it
never overstated it, and the assertion the story exists for fires verbatim,
naming both prescriptions.

**A second mutation, `## Notes` acceptance item 2, chosen independently of
GREEN's three.** Predicted by P3 as 4 assertions:

    $ bash scripts/mutate.sh .claude/skills/stack-profiles/reference/roblox-luau.md \
        's/ --cached --others --exclude-standard//' -- bash .claude/tests/profile-counters.test.sh
        FAIL no gate command in the profile uses a bare 'git ls-files'      (lines 75, 135, 136)
        FAIL every lint gate command carries the counting pipeline inline   (lines 75, 135)
        FAIL every typecheck gate command carries the counting pipeline inline  (line 136)
        FAIL comparison 3 - both counters use 'git ls-files --cached --others --exclude-standard'
             actual:   conf=ok/ok/ok profile=BAD/BAD/BAD
    profile-counters: 36 passed, 4 failed
    === mutate: ... restored (verified byte-for-byte ...) ===

4 predicted, 4 measured, all three offending lines named. Baseline re-confirmed
at `40 passed, 0 failed` afterwards; no `.bak` under `.claude/state/mutations/`.

**The diff was read, because nothing else will read it** (`## Contract`, "The
phase lock enforces nothing here either"). +120/−25 on the profile. The three
gate lines now match `project.conf`; the `COUNT(dirs)` macro is deleted and
replaced by a paragraph explaining why, which keeps
`selene src tests lune && COUNT(src tests lune)` as **prose** — the boundary in
Contract (c) working as designed. All four hazard bullets survive, two of them
extended with the `HARNESS-006` findings. Nothing was removed that was not
replaced by something that says more.

### One finding, not a defect, and not fixed here

**Assertions 35-37 are coarser than they read.** They are negative controls and
they do discriminate — they require the checker to report against a deliberately
defective prescription, and the paired clean fixture (38) stays green — but
because all four scans land in one concatenated string, they cannot say *which*
check spoke, and a future edit that broke one arm while leaving another firing
would not be noticed there. P1 against a real document is what has coverage at
that granularity, and it is a mutation rather than an assertion.

Not a return to RED: no assertion is vacuous, nothing is weakened, and the
property AC-7 names is verified. Recorded so the next person reading
`REGRESSED_FIXTURE` knows its resolution is one string, not four.

### GATES (2026-09-17)

**No deferred verifications to run.** The block is empty by design — every
control was producible in RED because the artifact already existed and was
already wrong. Fifteen `mutate.sh` runs across RED and GREEN are what stands in
for it, and `## Regressions` carries their output.

**No `## Gate probes` entry, because this story adds and changes no gate.** It
adds a *suite*, which `scripts/selftest.sh` discovers. The section is left as its
template comment rather than deleted so the harness's section readers still find
it.

**`bash scripts/gates.sh`: all 6 required gates pass, 3 unconfigured, 0 known, 0
blocked.** Recorded by the script into `## Gate results` above, stamped at commit
`d635f94`, tree `7dd91365`.

**Read that record with Contract (a) in hand.** It says *"All required gates
passed"*, and **no gate in it read this story's artifact.** The `harness` gate
runs `project-counters.test.sh` only; `profile-counters.test.sh` is named by no
`gate` line. That is the accepted design, not an oversight — the guard is
toolchain-free by requirement and reaches CI through `selftest.sh` in the required
`gates` job — but it is precisely the shape `/advance-story` warns about, so it is
written down rather than left for someone to infer from a green summary. What
actually verifies the artifact on this branch:

    $ bash .claude/tests/profile-counters.test.sh
    profile-counters: 40 passed, 0 failed
    $ bash scripts/selftest.sh profile-counters
    profile-counters: 40 passed, 0 failed
    1 harness suite(s) passed.

**The gate record survives committing the story, verified rather than assumed.**
`gate_tree_hash` (`.claude/hooks/lib.sh:650`) filters the listing through
`classify_stdin | gated_stdin`, so only gated paths are hashed and `docs/**` is
not among them. Recomputed with the story file dirty:

    7dd91365d27ad2d22361372720a82fa17e7d788f   recomputed, story file modified
    7dd91365d27ad2d22361372720a82fa17e7d788f   recorded in ## Gate results

Identical, so the REVIEW commit that carries this record cannot invalidate it.
