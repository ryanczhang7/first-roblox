# Profile: roblox-luau

Roblox experiences written in Luau, with the filesystem as the source of truth
and Studio demoted to a viewport. Rokit pins the toolchain, Rojo syncs and
builds, Wally resolves packages, and **Lune** runs tests and scripts headlessly —
which is the whole reason this stack is tractable for this harness. With Lune,
lint, type analysis, unit tests and a place build all run on Linux CI with no
Roblox credentials and no GUI.

> **Everything below is `# UNVERIFIED`.** None of this toolchain was installed
> on the machine where this profile was written, so every command here is a
> documented intention rather than an observed fact. The bootstrap story must
> run each one and correct this file against real output before any story
> depends on it. See `new-profile.md`, "Verify before you rely on it".

## The shape of the problem in this ecosystem

Read this before the gate table, because it determines most of what follows.

**Every tool in this stack is a Unix-style "print nothing when happy" tool.**
`stylua --check`, `selene` and `luau-lsp analyze` all exit 0 and emit little or
nothing on a clean run — and they exit 0 just as quietly when pointed at a
directory that does not exist, a glob that matches nothing, or a source tree
that was renamed out from under them. This ecosystem has no `cargo`-style
"Checked 47 files" line to lean on.

That makes `evidence` harder here than in any other profile, and it is solved
the same way each time: **make the gate command count its own inputs.** Do not
try to extract a number from a tool that does not print one.

    gate | lint | required | . | n=$(git ls-files 'src/**/*.luau' 'tests/**/*.luau' | wc -l); echo "selene over $n files"; selene src tests

The `echo` is not decoration. It is the gate asserting how much work it was
handed, from `git ls-files`, which cannot silently drift the way a shell glob
can. Every gate below uses this pattern except `unit`, which has a real runner
that counts for itself.

## Gate commands for project.conf

    # UNVERIFIED - see the banner above.
    gate | format    | optional | . | n=$(git ls-files '*.luau' | wc -l); echo "stylua over $n files"; stylua --check src tests lune
    gate | lint      | required | . | n=$(git ls-files 'src/**/*.luau' 'tests/**/*.luau' | wc -l); echo "selene over $n files"; selene src tests
    gate | typecheck | required | . | rojo sourcemap default.project.json --output sourcemap.json && n=$(git ls-files 'src/**/*.luau' | wc -l); echo "analyze over $n files"; luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --base-luaurc=.luaurc --ignore='Packages/**' src
    gate | unit      | required | . | lune run test
    gate | coverage  | optional | . |
    gate | build     | required | . | rojo build default.project.json --output build/place.rbxl && test -s build/place.rbxl && echo "built $(wc -c < build/place.rbxl) bytes"

    task | install | - | . | rokit install && wally install
    task | dev     | - | . | rojo serve default.project.json
    task | test    | - | . | lune run test

`rojo sourcemap` is **not a gate**. It is a prerequisite step that produces the
file `luau-lsp` needs to resolve `script.Parent` style references to real paths,
so it is chained into `typecheck` with `&&`. `sourcemap.json` is generated and
belongs in `.gitignore` — which is also what makes the phase lock classify it as
`ignored` rather than as frozen source.

`globalTypes.d.luau` is the Roblox API type dump. It is generated, not authored:
fetch it during `task install` and gitignore it. The bootstrap story must
establish where it comes from and pin that, because a stale dump produces
type errors that look like code errors.

`build` verifies the artefact is non-empty in the gate itself rather than
trusting Rojo's exit code, and prints the byte count so `evidence` has something
to read.

## Evidence of work

    # UNVERIFIED - correct these against real output in the bootstrap story.
    evidence | format    | stylua over [1-9][0-9]* files
    evidence | lint      | selene over [1-9][0-9]* files
    evidence | typecheck | analyze over [1-9][0-9]* files
    evidence | unit      | [1-9][0-9]* passed
    evidence | build     | built [1-9][0-9]* bytes

    floor    | unit      | 1
    floor    | lint      | 1

The `unit` regex assumes the runner contract in "Testing notes" below. If you
adopt a third-party framework instead, this line is the first thing to change,
and the floor has to be able to read the whole number out of it.

Raise the `unit` floor to a real number as soon as the suite has one — a floor
of 1 catches a suite that vanished entirely, not one that quietly shrank from
120 tests to 4. That is the failure this stack is most exposed to, because a
hand-rolled runner that fails to `require` a test file can easily skip it
rather than crash. Make the runner crash. See below.

## What the runner can see

    # UNVERIFIED
    discovery | tests | . | lune run test -- --list | grep -E '^[1-9][0-9]* test' > /dev/null

The `--list` mode is a **requirement on the runner you write**, not a flag that
exists by default. It must walk the same tree the real run walks, print the
count and each test name, and run nothing. That makes discovery genuinely
independent of the `unit` gate — which is more than `godot.md` can say, and the
payoff for controlling the runner.

The way a suite silently vanishes here: `tests/` is walked with a directory
listing, a rename or a moved folder drops out of the walk, and the run reports
"0 tests" with exit 0. The floor above is what catches it.

## The coverage story

**There is no working line-coverage path for Lune, and the coverage gate is
deliberately left unconfigured.** This was investigated rather than assumed:

- `debug.sethook` — the mechanism LuaCov and every Lua coverage tool is built
  on — does not exist in Luau. It was removed for sandboxing.
- The Luau VM *does* have first-class coverage support, via a `coverageLevel`
  compile option and a `lua_getcoverage` C API, which the upstream `luau` CLI
  uses to implement coverage reporting.
- Lune exposes the compile option — `luau.compile(src, { coverageLevel = 2 })` —
  but **no way to read the data back**. Its `@lune/luau` API is `compile` and
  `load`, and nothing else. You can instrument, and then you cannot ask.

So the honest options, in order of preference:

1. **Leave `coverage` unconfigured; lean on the mutation gate instead.** This
   harness already ships `scripts/mutate.sh` and a mutation-tester agent, and
   mutation is a strictly stronger signal than line coverage — it asks whether
   a test *fails when the behaviour changes*, which is the actual requirement in
   law 4. For a project whose highest-risk surface is a trust boundary, "does
   this test reject a malformed remote call" matters and "was this line
   executed" does not. Record the choice in `docs/wiki/stack.md`.
2. **Run the pure subset under the upstream `luau` CLI, which has coverage.**
   Logic with no Lune stdlib dependency — a round state machine, validation
   schemas, scoring — can execute under plain `luau` and be measured there. The
   cost is a second runner and a split suite; the benefit is real coverage over
   exactly the code that most deserves it. Worth it only if the pure core is
   large, which in a server-authoritative design it should be.
3. **Source instrumentation.** Preprocess `.luau` into counter-injected copies.
   Do not. It breaks line numbers in every stack trace, and the harness's whole
   value rests on trustworthy failure output.

Do not configure the gate with a command that measures nothing, and do not
delete the gate line — an unconfigured optional gate is visible; a missing one
is forgotten.

## What `--fast` should leave out

    slow | build | a full Rojo place build; RED and GREEN have no use for the .rbxl

Nothing else, and one thing deliberately kept in: **`typecheck` stays in the
fast subset** despite being the slowest of the three, because `--!strict` is
this project's primary correctness tool and the sourcemap step it depends on is
exactly the kind of thing that rots silently. A story that reaches GATES having
never run analysis is a story that wrote untyped Luau for an hour.

This profile's `coverage` gate is unconfigured, so unlike most stacks there is
no instrumented test run for `--fast` to protect. The plain `lune run test` *is*
the measurement. That is a weakness of the ecosystem, noted here rather than
hidden.

## Layout

    src/server/        authoritative logic. Round state machine, roles, voting, scoring
    src/client/        presentation only. Input, UI, camera, audio
    src/shared/        types, constants, pure functions, validation schemas
    src/net/           remote definitions + server-side validation wrappers
    tests/             Lune tests, mirroring src/ — tests/net/, tests/shared/, ...
    lune/test.luau     the test runner
    lune/build.luau    headless place build
    lune/analyze.luau  type analysis wrapper
    default.project.json   Rojo — committed
    rokit.toml             pinned toolchain — committed
    wally.toml/.lock       packages — both committed
    selene.toml stylua.toml .luaurc   committed

## paths.conf additions

Order matters — `paths.conf` takes the **first** matching rule, top to bottom.

Add to the `vendor` section (must come first, so package output never reads as
source):

    vendor | Packages/**
    vendor | ServerPackages/**
    vendor | DevPackages/**
    vendor | sourcemap.json
    vendor | globalTypes.d.luau

Add to the `test` section:

    test | tests/**
    test | **/*_test.luau
    test | **/*.spec.luau
    test | lune/test.luau

Add to the `manifest` section — `wally.toml` has a `[dev-dependencies]` block,
so RED can legitimately add a test-only package there:

    manifest | wally.toml
    manifest | wally.lock

Add to the `config` section:

    config | *.project.json
    config | rokit.toml
    config | selene.toml
    config | stylua.toml
    config | .luaurc
    config | lune/*.luau

Three of these are judgment calls worth stating out loud:

- **`wally.toml` is `manifest`, `rokit.toml` is `config`.** Wally resolves
  libraries your code imports and splits dev from production;
  `check-boundaries.sh` already parses `[dev-dependencies]` in TOML, so the RED
  dev-dependency check works on it unmodified. Rokit pins the *toolchain* —
  bumping Selene changes what the gates do, which is production surface and
  belongs in GREEN.
- **`lune/test.luau` is `test`; the other `lune/*.luau` are `config`.** The test
  runner is test infrastructure and RED must be able to fix it. The build and
  analyze scripts define what the gates mean and are frozen in RED like any
  other build config.
- **`sourcemap.json` and `globalTypes.d.luau` are generated.** They are listed
  as `vendor` *and* belong in `.gitignore`; either alone would do, both is
  deliberate, because a generated file misread as source is frozen in RED and
  the typecheck gate then cannot run.

## Notes for the bootstrap story

- **Verify every command in this file and delete the `UNVERIFIED` banners.**
  That is the bootstrap story's single most valuable output.
- Pin real versions in `rokit.toml` — whatever is current on the day, recorded
  in `docs/wiki/stack.md`. Do not copy version numbers out of a profile.
- **Prove the vacuous case fails.** Point `selene` at an empty directory and
  confirm the gate fails on evidence rather than passing. Do the same for
  `typecheck` with an empty `src`. This is the gate-probe requirement and in
  this ecosystem it is not a formality — these tools are silent by design.
- Establish where `globalTypes.d.luau` comes from, script it into
  `task install`, and gitignore it.
- Get `luau-lsp analyze` flags right early. It is the fiddliest command here,
  and the failure mode is an analysis that resolves nothing and reports zero
  errors — vacuous success, in the gate that matters most.
- A `.luaurc` with `"languageMode": "strict"` makes `--!strict` the default
  rather than a per-file opt-in. Prefer that to trusting 200 file headers, and
  add a guard test that every source file still carries the header if the brief
  requires it.
- CI runs Linux; Studio does not exist there and must not be required by any
  gate. If a gate needs Studio, it is not a gate.

## Testing notes

**The runner.** There is no single dominant Lune test framework the way `pytest`
or `vitest` dominates. Evaluate what exists at bootstrap, but the default
recommendation is **write the runner** — it is roughly 80 lines, and it converts
this profile's weakest property into its strongest: you control the output
format, so `evidence`, `floor` and `discovery` can be exact rather than scraped.

The contract it must satisfy:

- Walks `tests/` recursively for `*_test.luau`, `require`s each one.
- **A file that fails to load is a failure, never a skip.** This is the single
  most important line in the runner. A `require` wrapped in a silent `pcall` is
  how a suite quietly shrinks while staying green.
- Prints a final line matching `N passed, M failed` with real counts, and exits
  non-zero if `M > 0` **or if `N == 0`**. Zero tests is a failure, not a pass.
- Supports `--list`: same walk, prints `N tests` and each name, runs nothing.

**Faking time.** The round state machine is time-driven, and `os.clock` /
`task.wait` called directly make it untestable. Inject a clock as a constructor
argument from the very first story and keep the state machine a pure function of
`(state, event, now)`. This is an architecture decision, not a testing detail —
record it as an ADR, because retrofitting it later means rewriting the machine.

**Faking randomness.** Role assignment must be seedable for the same reason.
Pass a `Random` or a seed in; never call `math.random` at the point of use.

**What is theatre in this ecosystem.** A test that constructs a Roblox
`Instance` under Lune and asserts on its properties is testing `@lune/roblox`'s
datamodel emulation, not your game. Keep tests on the pure core — state machine,
validation, scoring, tally — where they are fast, deterministic and real.
Anything genuinely requiring the Roblox runtime is a Studio playtest step, not a
unit test, and should be written down as such rather than faked.

**Adversarial tests are the point.** In a server-authoritative design the
valuable test is not "a valid vote is counted" but "a vote from a dead player /
in the wrong phase / at 100 calls per second / with a table where a number
belongs is rejected". Every remote wrapper in `src/net/` gets those four.

## Prerequisites

**1. Rokit, the toolchain manager.** Everything else is installed *by* Rokit
from a committed `rokit.toml`, so this is the only genuine machine-level
install.

    # Windows — VERIFIED 2026-09-15: `winget search Rojo.Rokit` returns Rokit 1.2.0
    winget install --id Rojo.Rokit
    # macOS / Linux — UNVERIFIED
    curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash

Verify: `rokit --version`.

**2. The pinned tools.** After `rokit.toml` exists:

    rokit install

That must put `rojo`, `wally`, `selene`, `stylua`, `lune` and `luau-lsp` on
PATH **under exactly those names**, because that is how `project.conf` calls
them and what `scripts/doctor.sh` checks for.

Verify, each one: `rojo --version`, `wally --version`, `selene --version`,
`stylua --version`, `lune --version`, `luau-lsp --version`.

**3. Wally packages.** `wally install` populates `Packages/`, which is vendor
output and gitignored. Commit `wally.lock`.

**4. Nothing else.** No Roblox account, no Studio, no credentials are needed for
any gate in this profile. That is the defining property of this stack under this
harness and it should stay true — if a gate ever needs Studio, it is not a gate.

**Studio and an account** become necessary only for playtest verification and
publishing, both of which are human-initiated steps outside the gate loop.
Roblox Studio is Windows/macOS only; there is no Linux build, which is another
reason no gate may depend on it.
