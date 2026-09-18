---
id: HARNESS-010
title: The phase lock reads a sed expression as a path
slug: the-phase-lock-reads-a-sed-expression-as
epic: 
type: chore
status: done
phase: DONE
branch: claude/nostalgic-swanson-7f207e
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

**This story is a record of work already done, not a plan for work to do.** It
did not run a RED -> GREEN cycle, and the reason is the one sentence in
`CLAUDE.md` that governs this exact case:

> If it still blocks a command that writes nothing, that is a bug in the guard:
> add the case to `.claude/tests/phase-guard.test.sh` and fix it there, which is
> the one form of "working around the lock" that is allowed.

That carve-out is what was followed: the failing cases went in first, they were
watched to fail against the guard as it stood, and the hook was changed until
they passed. What that procedure does *not* produce is a story, a branch claimed
by one, or a `gates.sh` record. This file is here so the defect and its evidence
are in the backlog rather than only in a session transcript. `HARNESS-009` was
filed the same way, from a finding in `HARNESS-002`.

### The report

Raised by the test-developer during `SEAT-002`'s RED phase, as escalation 4:

> **The phase guard mis-read one command.** `f=.claude/tests/x.sh && sed -i -e
> 's/.../.../' "$f"` was refused as a write to path `s`, category `source` - it
> took the `-e` expression as the target. The real target was a harness file the
> phase permits; I used the Edit tool instead, which the guard judges by the real
> path. Reported so it can become a case in `.claude/tests/phase-guard.test.sh`;
> not routed around.

It did not block `SEAT-002`, and the escalation was handled correctly - reported,
not worked around. It is filed because a false refusal on a legitimate write is
expensive in this harness specifically: law 5 tells agents never to route around
a block, which only holds while blocks mean something.

### Two defects, and the first was hiding the second

**1. Parentheses were not masked inside a quoted span.** `maskchar` in
`.claude/hooks/lib.sh` masked the pipe, ampersand, semicolon, both angle
brackets, space and tab, and left parens alone. Every extractor in
`phase-guard.sh` terminates its match at `[^|&;()]`, so a quoted sed script
containing a BRE group - which is what an ordinary sed script looks like -
truncated the match mid-word, and `awk` taking the last field took the surviving
fragment for the write target. Reproduced against the guard as it stood, in a
fixture at RED:

    f=.claude/tests/project-counters.test.sh && sed -i -e 's/\(BASE_[A-Z]*\)=43/\1=47/' "$f"
        BLOCKED by the harness phase lock.
          path:     s
          category: source

The trigger is the paren, not `-e`. The same command with a group-free expression
parses correctly today and always did, which is why the shape in the escalation -
written with the expression elided to `s/.../.../` - looks unreproducible until
the group is put back.

**2. The sed rule's entire model of sed's argv was the last field.** The last
word is the file only when sed was handed a script and exactly one file. Probing
the guard rather than reading it turned up a **live hole**, not merely a nonsense
denial:

| Command, at RED, against the guard as it stood | Verdict |
|---|---|
| `sed -i --expression='s/\(a\)/b/' src/main.ts` | **not blocked at all** |
| `sed -i 's/a/b/' src/main.ts docs/notes.md` | **not blocked** - the last word is the second file |

The first slips through because the derived candidate is the option word itself,
which the candidate filter drops for starting with a dash; no target is derived
and frozen source is written unchallenged. This is the same shape `WORLD-080`
recorded for `-ni` and `-Ei`, and the same lesson: **a false positive and an open
hole are one defect read from two ends.** Fixing only the masking would have left
the guard naming an expression as a path whenever no file follows it.

## Acceptance criteria

<!-- Written alongside the tests rather than before them, because this repair
     ran under the CLAUDE.md carve-out above rather than as a cycle. They are
     recorded in the criteria idiom so each names the assertion that pins it;
     they were not frozen at a PLANNED boundary, and this note is here so that
     nobody reads them as though they had been. -->

- **AC-1** — Given a command whose quoted sed expression contains parentheses,
  when it writes a path the current phase permits, then the guard permits it.
  Pinned in `.claude/tests/phase-guard.test.sh` by the reported command itself,
  plus literal parens, a group in double quotes, and an ERE alternation.

- **AC-2** — Given the same expression shapes writing a path the phase freezes,
  then the guard refuses **on the file**, never on a fragment of the expression.
  Four controls, one per permitted case above.

- **AC-3** — Given an in-place sed with no file operand, then nothing is derived
  as a target: the argument of `-e` or `--expression=` is not a path.

- **AC-4** — Given an in-place sed naming more than one file, then **every** file
  operand is judged, not the last word.

- **AC-5** — Given `-f SCRIPT FILE`, then `SCRIPT` is read and not judged, and
  `FILE` still is.

- **AC-6** — Law 5 does not regress: a real in-place sed onto frozen production
  source is still refused, on the right path, in every shape the suite already
  covered (`-i`, `-i.bak`, `--in-place`, `--in-place=.bak`, `--i`, `-ni`, `-Ei`,
  a target held in a variable) and in the shapes this change adds (`-e`,
  `-i.bak -e`, `--expression=`, behind `-f`).

- **AC-7** — An unquoted paren is still shell syntax: `(cd src && echo x > a.ts)`
  is still refused on `src/a.ts`, not on a path ending in a paren. Pinned in
  `.claude/tests/lib.test.sh` at the masker, where the change is.

## The fix

**`.claude/hooks/lib.sh`** - `maskchar` masks the two parens to `\013` and
`\014`, and `unmask_shell_quotes` restores them. Those two bytes rather than the
next two free ones because `\011` is tab and `\012` is newline, and a masker
emitting either would be indistinguishable from the whitespace it is masking.
This is the root fix: it corrects every extractor at once - redirect, tee, cp and
mv, rm and touch, `shell_assignments` - not just the sed rule.

**`.claude/hooks/phase-guard.sh`** - the sed extractor now reads the words the
way sed reads them: options; the argument of an option that takes one (`-e`,
`-f`, `--expression`, `--file`, attached or separate); then operands, of which
the first is the *script* unless `-e` or `-f` already supplied one. Every file
operand is printed. `-i` still swallows the rest of its word as a backup suffix
(`-i.bak`), and the long options are still prefix-matched, so `--i` is
`--in-place` and `--silent` is not.

## Evidence

**The pre-fix run is the new tests against the pristine hooks**, extracted with
`git archive HEAD .claude` into a temp root and the two new suites copied over
it. The first attempt was discarded: edits landed while it was running, and a run
whose subject changed underneath it is not evidence of anything.

| Suite | Pristine hooks (`HEAD`) | After the fix |
|---|---|---|
| `.claude/tests/phase-guard.test.sh` | 186 passed, **11 failed** | 197 passed, 0 failed |
| `.claude/tests/lib.test.sh` | 143 passed, **4 failed** | 147 passed, 0 failed |

All 11 failures were in the new block; every pre-existing case passed against the
old hook, so the suite is not asserting something it already had. The reported
symptom appears verbatim in the failure output:

    FAIL blocks: control: a BRE group does not excuse an in-place write to source
         blocked, but on the wrong path (wanted 'src/main.ts'):
         ... path:     s   category: source

**The permits are not vacuous.** A candidate the guard cannot parse is *allowed*
after being logged to `.claude/state/phase-guard-declined.log` - so an
`assert_allowed` passes either way, and a fix that merely made the guard fail to
parse would satisfy every must-permit case. Each of the six new permits was
re-run with that log truncated first; all six leave it empty, meaning the guard
resolved the real target rather than giving up.

`bash scripts/selftest.sh`: **18 harness suites passed.**

## Notes

### Which story the gate run belongs to

`bash scripts/gates.sh` with no argument writes `## Gate results` into the
**active** story, and the active story throughout this work was `SEAT-002`, on
another branch. A record stamped against a tree that is not `SEAT-002`'s would be
a false stamp, so while this file did not exist the run named a story id with no
file behind it - every gate runs, and it prints `(not recorded: no story file
...)` rather than writing one. Once this story existed and claimed the branch,
the run was recorded here, by `gates.sh`, with `--story HARNESS-010`.

That is also how the gap was found. `check-boundaries.sh` resolves the claiming
story from the `branch:` frontmatter, not only from a `story/<ID>-` branch name,
so filing this record switched on the story checks that had been silent - and the
first thing they said was that a DONE story with no tool-written gate record is
not done.

### The worktree needed provisioning first

The first `selftest.sh` showed 7 failures in the `typecheck` gate. Cause:
`globalTypes.d.luau` - gitignored, fetched by `bash scripts/task.sh install` -
does not exist in a fresh worktree, so the gate's own `test -s` guard fails and
it exits 1 before `luau-lsp` runs. Unrelated to this change. After
`task.sh install`, `project-counters` went 33 passed / 7 failed to 40 / 0.
Recorded because the failure reads like a broken gate and is a missing artifact.

### What this does not fix

Each extractor in `phase-guard.sh` still carries its own idea of the command it
is reading: cp and mv take the last field, rm and touch take every non-option
word with a short list of option-argument exceptions, and sed now parses
properly. The cp rule has the same defect this story fixed in sed - taking the
last word is correct for an ordinary `cp a b dest`, but `cp -t src/ a b` names
its destination in an option argument and no rule knows it. Not filed as work,
because it is speculative until somebody hits it; noted so that the next person
who does has the shape already written down.

## Gate results

<!-- gates.sh: written by bash scripts/gates.sh; do not edit or paste by hand -->

    run:    2026-09-18T21:30:37Z
    commit: 29d0259 (working tree had uncommitted changes)
    tree:   a9ca1c708cb1f62afc87ca89dd9efc7e95abdd7e
    result: pass (6 ran, 3 unconfigured, 0 known)

    PASS         format (0s, observed 43)
    PASS         lint (0s, observed 43, floor 1)
    PASS         typecheck (3s, observed 8)
    PASS         unit (8s, observed 197, floor 197)
    UNCONFIGURED coverage
    UNCONFIGURED integration
    PASS         build (1s, observed 25103)
    PASS         harness (15s, observed 40)
    UNCONFIGURED mutation

