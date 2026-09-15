# Stack

> **Unverified.** Nothing in this file has been executed. Every version and
> every command below is researched, not verified. The bootstrap story must
> run each gate command, observe it fail on purpose, correct anything that
> has moved, and update both this file and `.claude/harness/project.conf`.

That banner is not boilerplate here; it is unusually load-bearing. **No part of
this toolchain is installed on the machine where this file was written.** Rokit,
Rojo, Wally, Lune, luau-lsp, Selene and StyLua are all absent, so not one command
below has been observed to run, fail, or print anything. The profile this file
draws on (`.claude/skills/stack-profiles/reference/roblox-luau.md`) carries the
same banner for the same reason.

The first story in the backlog, `BOOT-001`, exists chiefly to delete these
banners.

---

## 1. The stack is not chosen here — it was chosen by the brief

Product brief **B2** fixes every layer. This file does not re-open that decision;
it records it, attaches gate commands to it, and states what is still unknown.

| Layer | Choice | Version | Why (brief constraint) |
|---|---|---|---|
| Language | Luau, `--!strict` everywhere | ships with the runtimes below | B2. Strict mode is a gate, not a style preference (`typecheck`). |
| Toolchain manager | **Rokit** | pinned by `BOOT-001` | B2. One committed manifest pins every other tool, so CI and the operator's machine agree by construction. |
| Sync / build | **Rojo** | pinned by `BOOT-001` | B2. Filesystem is the source of truth; Studio is a viewport. Also produces the sourcemap `luau-lsp` needs and the `.rbxl` the `build` gate asserts. |
| Packages | **Wally** | pinned by `BOOT-001` | B2. `wally.lock` committed. Has a `[dev-dependencies]` block, which is what lets RED declare a test-only package (see §6). |
| Headless runtime | **Lune** | pinned by `BOOT-001` | B2, and the reason this stack is tractable at all: tests and builds run on Linux CI with no Roblox credentials and no GUI. |
| Types / analysis | **luau-lsp** (`analyze`) | pinned by `BOOT-001` | B2. Driven by Rojo's sourcemap. The `typecheck` gate. |
| Lint | **Selene** | pinned by `BOOT-001` | B2. |
| Format | **StyLua** | pinned by `BOOT-001` | B2. |
| Test runner | **hand-written, `lune/test.luau`** | n/a — ours | See §3. There is no dominant Lune test framework, and writing ~80 lines buys an exact output contract for `evidence`, `floor` and `discovery`. |
| Coverage | **none — deliberately unconfigured** | — | See §4. This is amendment 5 and it is the most consequential line in this file. |
| Deploy | Open Cloud API, scripted | not built in M0–M2 | B2, B1 #5 — gated behind operator approval. Out of scope until M6. |
| Studio bridge | official `studio-rust-mcp-server` | not used by any gate | B1 #3, B1 #4. Optional outer loop. **No gate may require Studio**; CI is Linux and Studio has no Linux build. |

### Why no version numbers

Every version cell above says "pinned by `BOOT-001`" rather than a number, and
that is a decision rather than laziness.

A version number written into a planning document by an agent with no network
verification and no installed toolchain is a **guess that reads like a fact**,
and the next agent — fresh context — will transcribe it into `rokit.toml` and
then spend an afternoon on a resolution error. The profile says the same thing
in one line: *"Do not copy version numbers out of a profile."*

So `BOOT-001` runs `rokit add` for each tool, lets Rokit resolve the current
release, commits `rokit.toml`, and **writes the resolved versions back into this
table**. That is the first thing this file will learn.

### Roblox is not a dependency of the inner loop

Worth stating plainly, because it is the defining property of this stack under
this harness and the thing most likely to be eroded by a well-meaning story:

- No gate needs a Roblox account.
- No gate needs Roblox Studio.
- No gate needs network access at run time.
- Every gate runs on `ubuntu-latest`.

**If a gate ever needs Studio, it is not a gate.** It is a playtest step, and it
belongs in `docs/wiki/game/playtest.md`, not in `project.conf`.

---

## 2. The problem this ecosystem has, and how the gates answer it

Read this before the gate table; it determines the shape of every command.

**Every tool here prints nothing when it is happy.** `stylua --check`, `selene`
and `luau-lsp analyze` exit 0 and emit nothing on a clean run — and they exit 0
just as quietly when pointed at a directory that does not exist, a glob that
matches nothing, or a source tree that was renamed out from under them. There is
no `cargo`-style "Checked 47 files" line anywhere in this ecosystem to hang an
`evidence` regex on.

That is the exact failure `evidence` lines exist for, and the usual answer —
scrape a number out of the tool's output — is unavailable because there is no
number.

**So each gate counts its own inputs and says so.**

    n=$(git ls-files 'src/**/*.luau' 'tests/**/*.luau' | wc -l); echo "selene over $n files"; selene src tests

The `echo` is the gate asserting how much work it was handed. It reads from
`git ls-files` rather than a shell glob, because a glob that matches nothing
expands to nothing and says nothing, while `git ls-files` returns the tracked
truth and `wc -l` turns it into a number a `floor` can read.

Two consequences worth naming:

- **The count comes from git, so an uncommitted new file is invisible to it.**
  That is acceptable — `git ls-files` lists tracked files, and a story's new
  source is tracked as soon as it is added. It is *not* acceptable to "fix" this
  by switching to a shell glob, which reintroduces the silent-zero.
- **A gate that passes quickly and quietly is the thing to be suspicious of.**
  `BOOT-001` must prove the vacuous case *fails* for each gate, not merely that
  the happy case passes. See §5.

---

## 3. The test runner is ours, and that is the point

There is no `pytest` or `vitest` for Lune. `BOOT-001` should look at what exists
on the day, but the recommendation standing behind this plan is **write the
runner**, at `lune/test.luau`.

It is roughly eighty lines and it converts this ecosystem's weakest property into
its strongest: we control the output format, so `evidence`, `floor` and
`discovery` become exact rather than scraped.

**The contract `BOOT-001` must satisfy:**

1. Walks `tests/` recursively for `*_test.luau` and `require`s each one.
2. **A file that fails to load is a failure, never a skip.** This is the single
   most important line in the runner. A `require` wrapped in a silent `pcall` is
   how a suite quietly shrinks from 120 tests to 4 while staying green.
3. Prints a final line matching `N passed, M failed` with real counts.
4. Exits non-zero if `M > 0` **or if `N == 0`**. Zero tests is a failure.
5. Supports `--list`: the same walk, printing `N tests` and each test name, and
   running nothing. This is what makes the `discovery` check genuinely
   independent of the `unit` gate rather than a second reading of the same run.

Point 5 is a requirement on code we are about to write, not a flag that exists
somewhere. If `BOOT-001` adopts a third-party framework instead, points 2, 4 and
5 are the acceptance test for that framework, and the `evidence` and `discovery`
lines below are the first things to change.

---

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

All `# UNVERIFIED`. `BOOT-001` runs each one, corrects it, and only then may any
later story trust it.

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

    # UNVERIFIED — BOOT-001 verifies and corrects every line.
    gate | format    | optional | . | n=$(git ls-files '*.luau' | wc -l); echo "stylua over $n files"; stylua --check src tests lune
    gate | lint      | required | . | n=$(git ls-files 'src/**/*.luau' 'tests/**/*.luau' | wc -l); echo "selene over $n files"; selene src tests
    gate | typecheck | required | . | rojo sourcemap default.project.json --output sourcemap.json && n=$(git ls-files 'src/**/*.luau' | wc -l); echo "analyze over $n files"; luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --base-luaurc=.luaurc --ignore='Packages/**' src
    gate | unit      | required | . | lune run test
    gate | coverage  | optional | . |
    gate | build     | required | . | rojo build default.project.json --output build/place.rbxl && test -s build/place.rbxl && echo "built $(wc -c < build/place.rbxl) bytes"

`rojo sourcemap` is **not a gate**. It is a prerequisite that produces the file
`luau-lsp` needs to resolve `script.Parent`-style references to real paths, so it
is chained into `typecheck` with `&&`. If it were its own gate it could pass
while producing a sourcemap that resolves nothing, and `typecheck` would then
analyse an empty world and report zero errors.

`build` verifies the artefact is non-empty **inside the gate** rather than
trusting Rojo's exit code, and prints the byte count so `evidence` has a number.

### Evidence and floors

    # UNVERIFIED — correct against real output in BOOT-001.
    evidence | format    | stylua over [1-9][0-9]* files
    evidence | lint      | selene over [1-9][0-9]* files
    evidence | typecheck | analyze over [1-9][0-9]* files
    evidence | unit      | [1-9][0-9]* passed
    evidence | build     | built [1-9][0-9]* bytes

    floor    | unit      | 1
    floor    | lint      | 1

The `unit` floor of 1 catches a suite that vanished entirely. It does **not**
catch one that shrank from 120 to 4, and with no coverage gate nothing else will
either — so **every story that adds tests raises this floor**, in that story, and
says the new number out loud. The story files in this backlog say so individually
because it is the single easiest discipline to let slip.

### Discovery

    # UNVERIFIED
    discovery | tests | . | lune run test -- --list | grep -E '^[1-9][0-9]* test' > /dev/null

This is the check that the runner can *see* the tests, asked of the runner rather
than of its configuration. It depends on the `--list` contract in §3. Written as
`grep PATTERN > /dev/null`, never `grep -q`: `grep -q` exits on first match, the
runner upstream takes SIGPIPE and dies 141, and the result is a spurious
"nothing discovered" that appears only once the listing is long enough to matter.

### `--fast`

    slow | build | a full Rojo place build; RED and GREEN have no use for the .rbxl

Nothing else, and one thing kept in deliberately: **`typecheck` stays in the fast
subset** despite being the slowest of the three static tools, because `--!strict`
is this project's primary correctness instrument and the sourcemap step it
depends on rots silently. A story that reaches GATES having never run analysis is
a story that wrote untyped Luau for an hour.

Note the asymmetry this stack has and most do not: with `coverage` unconfigured,
there is no instrumented test run for `--fast` to protect. `lune run test` *is*
the measurement. That is a weakness of the ecosystem, recorded rather than
hidden.

### `covers`

Left empty by this plan, **on purpose**. A `covers` line must say what a runner
can actually see, taken from the runner's real include list and backed by a
`discovery` line — not inferred from the directory layout. Nothing has been run,
so any line written here would be a guess the check would then believe.
`BOOT-001` writes them.

### Gate probes — the part of `BOOT-001` that cannot be redone cheaply

Because every tool in §2 is silent when idle, "the gate passed" carries almost no
information until the gate has been seen to fail. `BOOT-001` must break what each
gate guards and paste both outputs:

| Gate | The vacuous case it must be shown to reject |
|---|---|
| `lint` | `selene` pointed at a directory with no `.luau` in it — the `evidence` count must go to 0 and the gate must fail on evidence, not pass silently. |
| `typecheck` | an empty `src` — `analyze` exits 0 with nothing to say; the gate must fail. Also: a deliberate type error must fail it (this is M0's own definition of done). |
| `format` | a file with the indentation mangled. |
| `unit` | `mv tests tests.probe` — must fail on `N == 0`, not report success. |
| `build` | a `default.project.json` pointing at a path that does not exist — must fail on the `test -s`, not on Rojo's exit code alone. |

The `typecheck` row is the one to spend real time on. `luau-lsp analyze` is the
fiddliest command in this file and its failure mode is an analysis that **resolves
nothing and reports zero errors** — vacuous success in the gate that matters
most. The flags, the sourcemap, `globalTypes.d.luau` and `.luaurc` all have to be
right simultaneously, and only a deliberately introduced type error proves they
are.

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
authored**: `BOOT-001` must establish where it comes from, pin that source, fetch
it in `task install`, and gitignore it. A stale dump produces type errors that
look like code errors, which is an expensive hour.

---

## 7. Tasks

    task | install | - | . | rokit install && wally install    # UNVERIFIED; must also fetch globalTypes.d.luau
    task | dev     | - | . | rojo serve default.project.json
    task | test    | - | . | lune run test

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
