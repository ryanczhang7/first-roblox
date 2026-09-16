---
id: HARNESS-007
title: The roblox-luau profile still teaches the counter HARNESS-006 removed
slug: the-roblox-luau-profile-still-teaches-th
epic: 
type: chore
status: todo
phase: PLANNED
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

## Deferred verifications

<!-- Nothing is deferred. The artifact exists and is already wrong, so every
     control is producible in RED: a guard can be run against today's profile
     and watched to name the offending lines. The consequence is the one
     rules.md names and HARNESS-006 lived through - every assertion runs against
     text that already exists, so any assertion green on arrival is earned by
     mutating the profile through scripts/mutate.sh and pasting the output into
     ## Regressions. -->

## Model guidance

**Resolved model of every dispatch, by name:** _(record at dispatch.)_

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
