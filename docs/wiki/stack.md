# Stack

> **Verified 2026-09-15 by `BOOT-001`**, on Windows 11 / Git Bash, against the
> real toolchain. Every command below has been run; every required gate has
> additionally been observed to **fail on its vacuous case**. The failing and
> restored outputs are in `docs/backlog/stories/BOOT-001.md`, `## Gate probes`.
>
> Two things are still unverified and are marked inline where they appear:
> **Linux** (this machine is Windows; the first CI run is what confirms it) and
> the **macOS/Linux Rokit install line**.

What the banner used to say was that nothing in this file had been executed.
Running it changed six things, and they are recorded in place rather than in a
changelog: the version table below, the shape of the input count in §2, the
`typecheck` gate command in §5, the `slow` list, the source of
`globalTypes.d.luau` in §6, and the `task install` line in §7. The profile this
file draws on
(`.claude/skills/stack-profiles/reference/roblox-luau.md`) was corrected the same
way and by the same run.

---

## 1. The stack is not chosen here — it was chosen by the brief

Product brief **B2** fixes every layer. This file does not re-open that decision;
it records it, attaches gate commands to it, and states what is still unknown.

| Layer | Choice | Version | Why (brief constraint) |
|---|---|---|---|
| Language | Luau, `--!strict` everywhere | ships with the runtimes below | B2. Strict mode is a gate, not a style preference (`typecheck`). |
| Toolchain manager | **Rokit** | **1.2.0** (machine-level) | B2. One committed manifest pins every other tool, so CI and the operator's machine agree by construction. |
| Sync / build | **Rojo** | **7.7.0** | B2. Filesystem is the source of truth; Studio is a viewport. Also produces the sourcemap `luau-lsp` needs and the `.rbxl` the `build` gate asserts. |
| Packages | **Wally** | **0.3.2** | B2. `wally.lock` committed. Has a `[dev-dependencies]` block, which is what lets RED declare a test-only package (see §6). |
| Headless runtime | **Lune** | **0.10.5** | B2, and the reason this stack is tractable at all: tests and builds run on Linux CI with no Roblox credentials and no GUI. |
| Types / analysis | **luau-lsp** (`analyze`) | **1.69.0** | B2. Driven by Rojo's sourcemap. The `typecheck` gate. |
| Lint | **Selene** | **0.31.0** | B2. |
| Format | **StyLua** | **2.5.2** | B2. |
| Test runner | **hand-written, `lune/test.luau`** | n/a — ours | See §3. There is no dominant Lune test framework, and writing ~80 lines buys an exact output contract for `evidence`, `floor` and `discovery`. |
| Coverage | **none — deliberately unconfigured** | — | See §4. This is amendment 5 and it is the most consequential line in this file. |
| Deploy | Open Cloud API, scripted | not built in M0–M2 | B2, B1 #5 — gated behind operator approval. Out of scope until M6. |
| Studio bridge | official `studio-rust-mcp-server` | not used by any gate | B1 #3, B1 #4. Optional outer loop. **No gate may require Studio**; CI is Linux and Studio has no Linux build. |

### Where those numbers came from

Nobody typed them. Every cell above is what **Rokit resolved on 2026-09-15**
from `rokit add <owner>/<tool>` with no version specified; the resolved
identifiers are in `rokit.toml`, which is the actual pin, and this table is a
copy of it for readers.

A version number written into a planning document by an agent with no network
verification and no installed toolchain is a **guess that reads like a fact**,
and the next agent — fresh context — will transcribe it into `rokit.toml` and
then spend an afternoon on a resolution error. The profile says the same thing
in one line: *"Do not copy version numbers out of a profile."* The same rule
applies to this table now that it is populated: **`rokit.toml` is the pin; if
these disagree, `rokit.toml` is right.**

One correction worth carrying: `rokit add JohnnyMorganz/StyLua` installs the
tool under the alias **`StyLua`**, capitalised as the repository is, and every
gate command, `doctor.sh` and `environment.md` call it `stylua`. That is
invisible on Windows, whose filesystem is case-insensitive, and a
`command not found` on Linux CI. `rokit.toml` therefore carries an explicit
lowercase alias:

    stylua = "JohnnyMorganz/StyLua@2.5.2"

added with `rokit add JohnnyMorganz/StyLua stylua`.

### Roblox is not a dependency of the inner loop

Worth stating plainly, because it is the defining property of this stack under
this harness and the thing most likely to be eroded by a well-meaning story:

- No gate needs a Roblox account. **Verified** — nothing in `project.conf`
  authenticates against anything.
- No gate needs Roblox Studio. **Verified** — Studio is not installed on the
  machine these gates were run on.
- No gate needs network access at run time. **Verified** — the network is used by
  `task install` (Rokit, Wally, the type dump) and by nothing under
  `scripts/gates.sh`. Selene's Roblox standard library is built in, so even the
  linter is offline (§6).
- Every gate runs on `ubuntu-latest`. **UNVERIFIED** — every measurement in this
  file is Windows 11 / Git Bash. `.github/workflows/gates.yml` installs the
  toolchain and runs the suite there, and the first CI run on `BOOT-001`'s pull
  request is what settles it. The one known Windows-only hazard is already fixed:
  the `stylua` alias, below.

**If a gate ever needs Studio, it is not a gate.** It is a playtest step, and it
belongs in `docs/wiki/game/playtest.md`, not in `project.conf`.

---

## 2. The problem this ecosystem has, and how the gates answer it

Read this before the gate table; it determines the shape of every command.

**Every tool here prints nothing when it is happy** — and, measured rather than
assumed, they are not equally honest about having nothing to do:

| pointed at | `selene` | `stylua --check` | `luau-lsp analyze` |
|---|---|---|---|
| a directory that **exists and is empty** | exit 0, `0 errors` | exit 0, silent | exit 1, `error: no files provided` |
| a directory that **does not exist** | exit 1, `os error 2` | exit 0, silent | exit 1, `path does not exist` |

So the silent-zero is real, `selene` over an emptied tree is the clearest case
of it, and there is no `cargo`-style "Checked 47 files" line anywhere in this
ecosystem to hang an `evidence` regex on.

That is the exact failure `evidence` lines exist for, and the usual answer —
scrape a number out of the tool's output — is unavailable because there is no
number.

**So each gate counts its own inputs and says so.** The verified form:

    selene src tests lune && n=$(git ls-files -- src tests lune | while IFS= read -r f; do case "$f" in *.luau) if [ -e "$f" ]; then echo x; fi ;; esac; done | wc -l) && echo "selene over $n files"

The `echo` is the gate asserting how much work it was handed. Four things in
that line are the way they are because the obvious version was run first and was
wrong:

- **`git ls-files -- src tests lune` plus a per-path extension test, not
  `git ls-files 'src/**/*.luau'`.** In a git pathspec `**/` matches *one or more*
  directories, never zero, so the planned form does not match `src/Foo.luau` at
  all. Measured: `git ls-files 'lune/**/*.luau'` returns **0** on a tree
  containing `lune/test.luau`. It undercounts silently, which is the failure this
  whole section exists to prevent.
- **`[ -e "$f" ]`, because `git ls-files` reads the index, not the disk.** After
  `mv src src.probe` every source file is still tracked, so an unfiltered count
  keeps its old value, the evidence regex is satisfied, and the gate passes over
  a source tree that is not there. Tracked **and** present is the property the
  gates need.
- **`case`/`if` rather than `| grep -E '\.luau$'` and `[ -e ] && echo`.**
  `gates.sh` runs gate commands under `set -o pipefail`. On a tree with no
  `.luau` files `grep` exits 1, the whole `n=$(...)` assignment exits 1, the
  `&&` chain stops, and **the count line is never printed** — so the gate fails
  on an opaque `exit 1` instead of "ran but produced no evidence of work", which
  is the diagnosis this design exists to produce. Every stage of the count must
  exit 0 over an empty tree.
- **The `echo` comes *after* the tool.** `scripts/doctor.sh` takes the first
  token of each gate command as the executable to look for on PATH, so a command
  beginning `n=$(git ...` makes doctor report a permanently missing tool called
  `n=$(git`. The ordering costs nothing: `gates.sh` only consults the evidence
  regex for a gate that already exited 0.

Two consequences worth naming:

- **The count comes from git, so an uncommitted new file is invisible to it.**
  That is acceptable — a story's new source is tracked as soon as it is added. It
  is *not* acceptable to "fix" this by switching to a shell glob, which
  reintroduces the silent-zero.
- **A gate that passes quickly and quietly is the thing to be suspicious of.**
  `BOOT-001` proved the vacuous case *fails* for each gate, not merely that the
  happy case passes. See §5.

### The counted input is not enough for `typecheck`, and that was measured

The file count catches a gate handed **nothing**. It cannot catch a gate handed
everything and *understanding* none of it, and `luau-lsp analyze` has exactly
that failure mode. With `src` fully intact:

| given | prints | exits |
|---|---|---|
| `--sourcemap` at a file that does not exist | `[ERROR] Failed to load ... for workspace 'CLI'` | **0** |
| `--sourcemap` at JSON it cannot parse | `Sourcemap parsing failed, sourcemap is not loaded` | **0** |
| `--definitions` at a file that does not exist | `[ERROR] Failed to read definitions file ... Extended types will not be provided` | **0** |

In all three it carries on with no DataModel and/or no Roblox types, resolves
almost nothing, finds nothing wrong, and **exits 0** — vacuous success in the
gate this project's correctness rests on, with every file present and counted.
So the `typecheck` gate pipes the analyser through a filter that fails on either
shape:

    ... | awk '{print} /^\[ERROR\]|Sourcemap parsing failed/{bad=1} END{exit (bad?1:0)}'

and asserts `test -s globalTypes.d.luau` before running at all. A real
`TypeError` does not match that pattern, so the two are never confused.

---

## 3. The test runner is ours, and that is the point

There is no `pytest` or `vitest` for Lune. `BOOT-001` **wrote the runner**, at
`lune/test.luau`: 148 lines including its header, and it converts this
ecosystem's weakest property into its strongest — we control the output format,
so `evidence`, `floor` and `discovery` are exact rather than scraped.

A test file returns a table of `[name] = function()`; assertions are plain
`assert`, and nothing in this stack needs an assertion library.

**The contract, and all five points are verified:**

1. Walks `tests/` recursively for `*_test.luau` and `require`s each one.
2. **A file that fails to load is a failure, never a skip.** This is the single
   most important line in the runner. A `require` wrapped in a silent `pcall` is
   how a suite quietly shrinks from 120 tests to 4 while staying green.
3. Prints a final line matching `N passed, M failed` with real counts.
4. Exits non-zero if `M > 0` **or if `N == 0`**. Zero tests is a failure.
5. Supports `--list`: the same walk, printing `N tests` and each test name, and
   running nothing. This is what makes the `discovery` check genuinely
   independent of the `unit` gate rather than a second reading of the same run.

Point 2 is implemented as a `pcall` that **counts the failure** rather than one
that moves on, plus two cases the plan did not name and the implementation found:
a module that returns something other than a table, and a `*_test.luau` file that
returns an **empty** table. Both are load failures, because both are how a suite
shrinks without anyone noticing. Measured: a test file with an unresolvable
`require` gives `4 passed, 1 failed`, exit 1, with the load error printed to
stderr; `--list` exits 1 on the same tree while still printing what it could see.

Point 4's `N == 0` half was mutated out to see what it is worth, and the answer
is more interesting than "the gate would pass":

| with `tests/` moved aside | runner as written | `passed == 0` deleted |
|---|---|---|
| `lune run test` | `0 passed, 0 failed`, **exit 1** | `0 passed, 0 failed`, **exit 0** |
| `gates.sh --gate unit` | FAIL (exit 1) | FAIL — *no evidence of work* |

So the gate is double-netted: the runner's exit code and the `evidence` regex
catch it independently. The `N == 0` check is still load-bearing, because
**RED, GREEN and `task test` run `lune run test` directly**, where no evidence
line applies — and that is precisely where a vanished suite would read as green.

---


### An `assert` message is truncated at 512 characters, and the evidence goes with it

Found by `ROUND-004`'s RED when a failure message was cut mid-trail, and measured
by the Lead PO on a different input rather than taken on report. Lune 0.10.5,
this machine, 2026-09-16 — a message of `string.rep("A", n)` through
`pcall(function() assert(false, msg) end)`:

    message   400 chars -> err   444 chars,   401 A's kept
    message   480 chars -> err   524 chars,   481 A's kept
    message   500 chars -> err   544 chars,   501 A's kept
    message   520 chars -> err   555 chars,   512 A's kept
    message   600 chars -> err   555 chars,   512 A's kept
    message  2000 chars -> err   555 chars,   512 A's kept

**512 characters of message, exactly** — a fixed buffer, not a soft limit — plus
the `path:line:` prefix the runner adds, which is another 40-75 characters and is
*not* counted against the 512.

This matters here more than it would in most repositories. This project has no
coverage gate (§4), so a failing assertion's **message** is a large part of how a
defect gets diagnosed, and the house style writes long ones that name the
criterion, quote the expected and actual values and explain why the rule exists.
A message that puts the values last loses exactly the part worth reading.

So: **put the numbers first and the essay second.** Lead with the criterion, the
measured value and the wanted value; put the rationale after them, where losing
it costs nothing. Where a list has to be shown in full - a seat order, an effect
sequence - render it before the prose, and prefer a count plus the first
divergence over dumping both lists when either could be long.

## 4. Coverage: deliberately unconfigured, and what replaces it

**Decision (product brief §0b, amendment 5): the `coverage` gate is left with no
command and demoted from `required` to `optional`.** This section is the record
amendment 5 asks for.

### Why there is no coverage

Investigated, not assumed:

- `debug.sethook` — the mechanism LuaCov and every Lua coverage tool is built on
  — **does not exist in Luau**. It was removed for sandboxing.
- The Luau VM *does* have first-class coverage support: a `coverageLevel` compile
  option and a `lua_getcoverage` C API, which the upstream `luau` CLI uses to
  implement coverage reporting.
- Lune exposes the compile option — `luau.compile(src, { coverageLevel = 2 })` —
  and **no way to read the data back**. Its `@lune/luau` API is `compile` and
  `load`, and nothing else. You can instrument, and then you cannot ask.

So there is no honest coverage command for the runtime our tests run in. A
command that reports a number it did not measure is worse than no command, and
deleting the gate line entirely is worse again: an unconfigured optional gate is
visible in every `gates.sh` run; a missing one is forgotten.

### What replaces it, concretely

Coverage was doing two jobs. Both need new owners, and neither is "nothing".

**Job 1 — "did the tests execute this code at all?"** Replaced by the
**`floor` on the `unit` gate**, raised deliberately in the story that adds the
tests. With no coverage gate, the floor is now the *only* automated thing
standing between this project and a suite that quietly shrinks. Treat lowering a
floor as equivalent to deleting test cases, because here it is.

**Job 2 — "do the tests fail when the behaviour changes?"** Replaced by
**mutation**, in two forms, one mandatory and one optional:

- *Mandatory, every story:* `CLAUDE.md` law 4 and the orchestrator's verification
  ladder already require a mutation run against the committed implementation
  before a story is accepted, via `bash scripts/mutate.sh`. On this stack that
  stops being a nicety and becomes the primary coverage instrument. Each story in
  this backlog carries at least one predicted mutation for the orchestrator to
  run, recorded in `## Notes`.
- *Optional, periodically:* `/audit-mutations`. The `mutation` gate stays declared
  and unconfigured; there is no off-the-shelf Luau mutation runner and writing one
  is a project of its own, deliberately not in M0–M2.

Mutation is a strictly stronger signal than line coverage — it asks whether a
test *fails when the behaviour changes*, which is the actual requirement — and
for a project whose highest-risk surface is a trust boundary, "does this test
reject a malformed remote call" matters and "was this line executed" does not.

### The alternative that lost, and the condition that would revive it

**Run the pure subset under the upstream `luau` CLI, which does have coverage.**
Logic with no Lune stdlib dependency — the round phase machine, the seat
assignment, the validation schemas, the instance generator — can execute under
plain `luau` and be measured there. In a server-authoritative design that pure
core is most of the code, and it is exactly the code that most deserves
measuring.

It lost on three counts, none of them permanent:

1. `luau` is **not in B2's toolchain**, and B1 #5 requires operator approval
   before adding a dependency.
2. It means a second runner and a split suite — two commands that can disagree
   about what a test is — landing in the bootstrap story, which the sizing rule
   says is the worst possible place to put anything optional.
3. The mutation discipline above has not yet been shown to be insufficient.

**Revive it when:** an `/audit-mutations` pass reports that mutation coverage is
not reaching a body of pure logic, *or* a story needs to make a claim about
untested branches that mutation cannot make cheaply. At that point it is its own
story, with an operator decision on the new dependency attached.

---

## 5. Gates

All verified by `BOOT-001` and all observed to fail on their vacuous case. The
authority is `.claude/harness/project.conf`; this section says what each gate
means and why it is shaped the way it is.

| Gate | Required | What it actually asserts |
|---|---|---|
| `format` | optional | StyLua agrees with the committed formatting, over a counted file set. |
| `lint` | required | Selene finds nothing, over a counted file set. |
| `typecheck` | required | Rojo produces a sourcemap, then `luau-lsp analyze` reports zero errors over a counted file set. |
| `unit` | required | `lune run test` — our runner, real counts, non-zero exit on zero tests. |
| `coverage` | optional, **unconfigured** | nothing. See §4. |
| `integration` | optional, unconfigured | nothing in M0–M2. There is no service and no browser. |
| `build` | required | `rojo build` produces a **non-empty** `.rbxl`, byte count printed. |
| `mutation` | optional, unconfigured | nothing automated. See §4. |

### Commands

The exact, verified lines live in `.claude/harness/project.conf`; they are long,
and duplicating them here is how the two drift apart. What changed against the
plan, and why:

| gate | change | why |
|---|---|---|
| all counted gates | `git ls-files -- <dirs>` + per-path `case`/`[ -e ]` instead of `git ls-files 'src/**/*.luau'` | §2: `**/` never matches zero directories; the index is not the disk; `pipefail` swallows the count line |
| all counted gates | the `echo` moved **after** the tool | `doctor.sh` reads the first token of each command as the executable |
| `lint`, `format` | `lune` added to the target list | the test runner is real code and was linted by nothing |
| `typecheck` | `test -s globalTypes.d.luau` before, `awk` filter after | §2: three ways for `analyze` to resolve nothing and exit 0 |
| `build` | `mkdir -p build &&` added | `build/` is gitignored, so it does not exist in a clean checkout, and Rojo does **not** create the parent directory — measured: `[ERROR rojo] failed to create file 'build/place.rbxl' ... (os error 3)` |

`rojo sourcemap` is **not a gate**. It is a prerequisite that produces the file
`luau-lsp` needs to resolve `script.Parent`-style references to real paths, so it
is chained into `typecheck` with `&&`. If it were its own gate it could pass
while producing a sourcemap that resolves nothing, and `typecheck` would then
analyse an empty world and report zero errors — which §2 shows is not
hypothetical: with `src` emptied, `rojo sourcemap` **exits 0** and writes a
sourcemap that makes `luau-lsp` print *"Sourcemap parsing failed"* and carry on.

`build` verifies the artefact is non-empty **inside the gate** rather than
trusting Rojo's exit code, and prints the byte count so `evidence` has a number.
Honest correction to the plan: on Rojo 7.7.0 the exit code turns out to be
enough — a `$path` pointing at nothing produces a loud `[ERROR rojo]` and exit 1,
and no way was found to make Rojo exit 0 over a zero-byte place. `test -s` stays
as defence in depth, and its limb was exercised directly (exit 1 on a
deliberately truncated `place.rbxl`) rather than left as an untested branch.

### Evidence and floors

    evidence | format    | stylua over [1-9][0-9]* files
    evidence | lint      | selene over [1-9][0-9]* files
    evidence | typecheck | analyze over [1-9][0-9]* files
    evidence | unit      | [1-9][0-9]* passed, [0-9]+ failed
    evidence | build     | built [1-9][0-9]* bytes

    floor    | unit      | 1
    floor    | lint      | 1

The `unit` regex gained its second half in `BOOT-001`. The runner's summary line
is `N passed, M failed`; requiring both halves means the match cannot be
satisfied by a stray "3 passed" inside a test name, and the `floor` then reads
the pass count rather than whatever digits it found first.

Observed on the scaffold: `format` 3, `lint` 3, `typecheck` 1, `unit` 4,
`build` 1931 (bytes).

The `unit` floor of 1 catches a suite that vanished entirely. It does **not**
catch one that shrank from 120 to 4, and with no coverage gate nothing else will
either — so **every story that adds tests raises this floor**, in that story, and
says the new number out loud. The story files in this backlog say so individually
because it is the single easiest discipline to let slip.

### Discovery

    discovery | tests     | . | lune run test -- --list | grep -E '^[1-9][0-9]* tests?' > /dev/null
    discovery | shared    | . | lune run test -- --list | grep -E 'tests/shared/' > /dev/null
    discovery | sourcemap | . | rojo sourcemap default.project.json --output sourcemap.json && grep -F 'src/shared/Scaffold.luau' sourcemap.json > /dev/null

Two lines were added by `BOOT-001` beyond the planned one. `shared` is what makes
`covers | unit | src/shared/**` an observation rather than a claim. `sourcemap`
asks **Rojo** whether its mapping reaches a real file on disk, which is the only
independent check on the failure mode §2 measured — a sourcemap that resolves
nothing while every tool involved exits 0.

This is the check that the runner can *see* the tests, asked of the runner rather
than of its configuration. It depends on the `--list` contract in §3. Written as
`grep PATTERN > /dev/null`, never `grep -q`: `grep -q` exits on first match, the
runner upstream takes SIGPIPE and dies 141, and the result is a spurious
"nothing discovered" that appears only once the listing is long enough to matter.

### `--fast`

    slow | integration | needs a browser or a running service; minutes, not seconds
    slow | mutation    | re-runs the suite once per mutant

**`slow | build` was planned and has been deleted.** Measured on this machine,
warm: `format` 219 ms, `lint` 224 ms, `unit` 155 ms, `rojo sourcemap` 698 ms,
`luau-lsp analyze` 2,256 ms, **`rojo build` 125 ms** — the place build is the
*cheapest* command in the stack, faster than the linter. Excluding it from
`--fast` bought nothing and cost RED and GREEN the one gate that notices a broken
`default.project.json`. That is what "a gate is FAST unless somebody said
otherwise out loud" is for; the plan said it out loud on a guess, and measuring
it took four minutes.

One thing kept in deliberately: **`typecheck` stays in the fast
subset** despite being the slowest of the three static tools, because `--!strict`
is this project's primary correctness instrument and the sourcemap step it
depends on rots silently. A story that reaches GATES having never run analysis is
a story that wrote untyped Luau for an hour.

Note the asymmetry this stack has and most do not: with `coverage` unconfigured,
there is no instrumented test run for `--fast` to protect. `lune run test` *is*
the measurement. That is a weakness of the ecosystem, recorded rather than
hidden.

### `covers`

    covers | lint      | src/**
    covers | typecheck | src/**
    covers | build     | src/**
    covers | unit      | src/shared/**

Taken from what each tool was observed to read, and backed by the `discovery`
lines above. `selene` and `luau-lsp` are handed `src` whole; Rojo maps all four
subtrees through `default.project.json`.

**`unit` is narrower on purpose.** `lune run test -- --list` reports four tests,
all under `tests/shared/`, and the only production module any of them requires is
`src/shared/Scaffold.luau`. A `covers | unit | src/**` here would be a lie the
check would believe — and the whole value of these lines is that the run **fails**
when a story adds `src/server/` code no required test gate reads. `ROUND-001` and
`NET-001` widen it as they add the suites that justify it.

### Gate probes — the part of `BOOT-001` that cannot be redone cheaply

Because every tool in §2 is silent when idle, "the gate passed" carries almost no
information until the gate has been seen to fail. Every row below was run; the
pasted outputs are in `docs/backlog/stories/BOOT-001.md`, `## Gate probes`.

| Gate | What was broken | How it failed |
|---|---|---|
| `lint` | every `.luau` moved out, directories left in place | selene exit 0, `0 errors`; gate FAIL — *ran but produced no evidence of work*, log reads `selene over 0 files` |
| `typecheck` | `src` emptied of `.luau` | `Sourcemap parsing failed`, then `error: no files provided`, exit 1; gate FAIL |
| `typecheck` | `globalTypes.d.luau` removed | gate FAIL at the `test -s` guard, before the analyser ran |
| `typecheck` | `$path` repointed at a directory that does not exist | `[ERROR rojo] ... could not be turned into a Roblox Instance`, exit 1; gate FAIL |
| `typecheck` | a deliberate type error (`return out` → `return #out`) | `Scaffold.luau [game/ReplicatedStorage/Shared/Scaffold](36,2): TypeError: Expected this to be 'string', but got 'number'`; gate FAIL |
| `format` | one line's indentation mangled | `stylua --check` printed the diff, exit 1; gate WARN (optional) |
| `unit` | `mv tests tests.probe` | `0 passed, 0 failed`, exit 1; gate FAIL |
| `build` | `$path` repointed at a directory that does not exist | `[ERROR rojo]`, exit 1; gate FAIL |
| `build` | `place.rbxl` truncated to zero bytes | the `test -s` limb exits 1 |

The `typecheck` rows were where the time went, and they paid for themselves. The
plan expected `luau-lsp analyze` to be the vacuous one and `rojo` to be honest;
it is the other way round on these versions. `analyze` over nothing is honest
(`error: no files provided`, exit 1) — but `analyze` over **everything**, with a
sourcemap or a definitions file it could not load, resolves nothing, reports zero
errors and exits 0. That is the real hazard, the file count cannot see it, and
the `awk` filter in §2 is the answer. The `build` row was wrong in the plan's
favour too: Rojo's exit code is enough, and `test -s` is defence in depth.

Also verified, since it is what makes `--!strict` a default rather than 200 file
headers: with `.luaurc` flipped to `"languageMode": "nonstrict"` via
`scripts/mutate.sh`, a function returning `string?` where `string` is declared
**passes silently, exit 0**; under `"strict"` it is a `TypeError` and exit 1. The
`.luaurc` is load-bearing, and nil-safety is what it buys.

---

## 6. Path classification, and what RED may write

`.claude/harness/paths.conf` is updated by this plan for this stack. Three
classifications are judgment calls and are stated here so they are arguable:

- **`wally.toml` is `manifest`; `rokit.toml` is `config`.** Wally resolves
  libraries the code imports and has a `[dev-dependencies]` block, which
  `check-boundaries.sh` already parses — so RED can legitimately add a test-only
  package. Rokit pins the **toolchain**: bumping Selene changes what the gates do,
  which is production surface and belongs in GREEN.
- **`lune/test.luau` is `test`; every other `lune/*.luau` is `config`.** The test
  runner is test infrastructure and RED must be able to fix it. `build.luau` and
  `analyze.luau` define what the gates *mean* and are frozen in RED like any other
  build configuration.
- **`sourcemap.json` and `globalTypes.d.luau` are `vendor` *and* gitignored.**
  Either alone would do; both is deliberate. A generated file misread as source is
  frozen during RED, and the `typecheck` gate then cannot run.

`globalTypes.d.luau` is the Roblox API type dump. It is **generated, not
authored**, and `BOOT-001` established where it comes from:

    https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/<version>/scripts/globalTypes.d.luau

**Pinned to the `luau-lsp` version in `rokit.toml`, not to `main`.** The dump and
the analyser that reads it move together; a dump from a different day produces
type errors that look like code errors, which is an expensive hour. `task
install` reads the version out of `rokit.toml` with `sed` so the two cannot
drift, and asserts the result is non-empty:

    v=$(sed -n 's/^luau-lsp = ".*@\(.*\)"$/\1/p' rokit.toml)

Checked alternatives, so nobody re-checks them: the `luau-lsp` **release assets**
carry only the four platform zips and `Luau.rbxm`, no type dump; the repository
also publishes per-security-level variants (`globalTypes.None.d.luau` and
friends) which are **not** what `analyze --definitions` wants for a place build.
Measured for `1.69.0`: 806,997 bytes, HTTP 200 at the tagged path.

Selene needs no equivalent. Its `roblox` standard library is **built in** to
0.31.0 — verified both ways, `game`/`workspace`/`Instance.new` resolve clean and
an undefined global still raises `error[undefined_variable]` — so there is no
`selene generate-roblox-std` step, no generated `roblox.toml`, and the `lint`
gate needs no network.

---

## 7. Tasks

    task | install | - | . | rokit install --no-trust-check && wally install && <fetch globalTypes.d.luau, pinned; see §6>
    task | dev     | - | . | rojo serve default.project.json
    task | test    | - | . | lune run test
    task | fmt     | - | . | stylua src tests lune
    task | lint    | - | . | selene src tests lune
    task | analyze | - | . | luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --base-luaurc=.luaurc --ignore='Packages/**' src
    task | deps    | - | . | wally install

`--no-trust-check` is deliberate and it is not only for CI: without it Rokit
**prompts** before installing a tool it has not seen, and a prompt in the one
command every fresh checkout runs is a command that hangs an agent forever. The
trust boundary is the committed `rokit.toml` — six tools at exact versions,
reviewed like any other config change, classified `config` so RED cannot touch
it.

`task lint` duplicates the lint gate's tool on purpose: `doctor.sh` checks only
the **first token** of each gate and task command, and `selene` is the lint
gate's first token only by the ordering §2 describes. This line is what keeps
selene checked if that ever changes.

Verified from a stripped tree (`globalTypes.d.luau`, `sourcemap.json`,
`Packages/` and `build/` all deleted): `bash scripts/task.sh install` exits 0 and
prints `globalTypes.d.luau for luau-lsp 1.69.0: 806997 bytes`. `bash
scripts/task.sh dev` was started and `GET http://localhost:34872/api/rojo`
answered with `serverVersion 7.7.0`, `projectName first-roblox`.

`task dev` starts a Rojo server that Studio connects to. It is the closest thing
this stack has to "run the app", and it is **not** a gate: it needs a human and a
Studio install. On CI it is never invoked.

---

## 8. What this file does not cover

**Scope of this planning pass is M0–M2 only** (see `docs/wiki/architecture.md`
§0). Consequently this file says nothing about:

- Open Cloud deployment scripting (M6, operator-gated per B1 #5).
- Any Wally package. M0–M2 needs none: the phase machine, the seat ring, the
  validation wrappers and the telemetry envelope are all pure Luau. The first
  real dependency question arrives with M3, and B1 #5 makes it an operator
  decision.
- Client-side anything. M0–M2 builds no UI, so no rendering, no state management
  and no asset pipeline is chosen here.
- Persistence (DataStore request budgets, ordered stores, throttling). Telemetry
  in M2 emits through an **injected sink**; what that sink is on a live server is
  an M5 decision, and the architecture document says why the interface is drawn
  where it is.
