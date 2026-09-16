# Profile: roblox-luau

Roblox experiences written in Luau, with the filesystem as the source of truth
and Studio demoted to a viewport. Rokit pins the toolchain, Rojo syncs and
builds, Wally resolves packages, and **Lune** runs tests and scripts headlessly —
which is the whole reason this stack is tractable for this harness. With Lune,
lint, type analysis, unit tests and a place build all run on Linux CI with no
Roblox credentials and no GUI.

> **Verified 2026-09-15**, on Windows 11 / Git Bash, against Rokit 1.2.0,
> Rojo 7.7.0, Wally 0.3.2, Lune 0.10.5, Selene 0.31.0, StyLua 2.5.2 and
> luau-lsp 1.69.0. Every command below has been run, and every gate has been
> observed to fail on its vacuous case. **Linux verified 2026-09-16** by CI on
> `ubuntu-24.04`, at the same seven versions; **macOS is still unverified**, and
> the lines that depend on the platform say so where they appear.
>
> Do not copy the version numbers. They are here to say what was measured, not
> what to pin - run `rokit add` and let Rokit resolve the day's releases.

## The shape of the problem in this ecosystem

Read this before the gate table, because it determines most of what follows.

**Every tool in this stack is a Unix-style "print nothing when happy" tool** -
and, measured rather than assumed, they are not equally honest about having
nothing to do:

| pointed at | `selene` | `stylua --check` | `luau-lsp analyze` |
|---|---|---|---|
| a directory that **exists and is empty** | exit 0, `0 errors` | exit 0, silent | exit 1, `error: no files provided` |
| a directory that **does not exist** | exit 1, `os error 2` | exit 0, silent | exit 1, `path does not exist` |

So the silent-zero is real, and this ecosystem has no `cargo`-style "Checked 47
files" line to lean on.

That makes `evidence` harder here than in any other profile, and it is solved
the same way each time: **make the gate command count its own inputs.** Do not
try to extract a number from a tool that does not print one. The verified form:

    gate | lint | required | . | selene src tests lune && n=$(git ls-files -- src tests lune | while IFS= read -r f; do case "$f" in *.luau) if [ -e "$f" ]; then echo x; fi ;; esac; done | wc -l) && echo "selene over $n files"

That is uglier than it looks like it needs to be, and every part of it earns its
place. The obvious version -
`n=$(git ls-files 'src/**/*.luau' | wc -l); echo ...; selene src tests` - was
what this profile used to recommend, and it is wrong in four separate ways:

- **`git ls-files 'src/**/*.luau'` does not match `src/Foo.luau`.** In a git
  pathspec `**/` matches one or more directories, never zero. Measured:
  `git ls-files 'lune/**/*.luau'` returns 0 on a tree containing
  `lune/test.luau`. Use a directory pathspec and test the extension per path.
- **`git ls-files` reads the index, not the disk.** After `mv src src.probe`
  every file is still tracked, so the count keeps its old value, the evidence
  regex is satisfied, and the gate passes over a source tree that is not there.
  `[ -e "$f" ]` is what makes it *tracked and present*.
- **`gates.sh` runs gate commands under `set -o pipefail`.** A `| grep -E
  '\.luau$' |` stage exits 1 on an empty tree, which takes the whole `n=$(...)`
  assignment with it, which breaks the `&&` chain, and **the count line is never
  printed** - so the gate fails on an opaque `exit 1` instead of "ran but
  produced no evidence of work". Same reason the body is `if [ -e ]; then ... fi`
  rather than `[ -e ] && ...`, whose false branch makes the `while` loop exit 1.
  Every stage of the count must exit 0 over an empty tree.
- **The `echo` goes AFTER the tool, not before.** `scripts/doctor.sh` takes the
  first token of each gate command as the executable to look for on PATH, so a
  command beginning `n=$(git ...` makes doctor report a permanently missing tool
  called `n=$(git`. Ordering costs nothing: `gates.sh` only consults the evidence
  regex for a gate that already exited 0.

Every gate below uses this pattern except `unit`, which has a real runner that
counts for itself.

## Gate commands for project.conf

Let `COUNT(dirs)` stand for the counting pipeline above, to keep these readable:

    n=$(git ls-files -- <dirs> | while IFS= read -r f; do case "$f" in *.luau) if [ -e "$f" ]; then echo x; fi ;; esac; done | wc -l)

    gate | format    | optional | . | stylua --check src tests lune && COUNT(src tests lune) && echo "stylua over $n files"
    gate | lint      | required | . | selene src tests lune && COUNT(src tests lune) && echo "selene over $n files"
    gate | typecheck | required | . | rojo sourcemap default.project.json --output sourcemap.json && test -s globalTypes.d.luau && luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --base-luaurc=.luaurc --ignore='Packages/**' src 2>&1 | awk '{print} /^\[ERROR\]|Sourcemap parsing failed/{bad=1} END{exit (bad?1:0)}' && COUNT(src) && echo "analyze over $n files"
    gate | unit      | required | . | lune run test
    gate | coverage  | optional | . |
    gate | build     | required | . | mkdir -p build && rojo build default.project.json --output build/place.rbxl && test -s build/place.rbxl && echo "built $(wc -c < build/place.rbxl) bytes"

    task | install | - | . | rokit install --no-trust-check && wally install && <fetch globalTypes.d.luau, pinned - see below>
    task | dev     | - | . | rojo serve default.project.json
    task | test    | - | . | lune run test
    task | fmt     | - | . | stylua src tests lune
    task | lint    | - | . | selene src tests lune

Lint and format cover `lune` as well as `src` and `tests`. The test runner you
are about to write is real code and the planned command left it unlinted.

`--no-trust-check` on `rokit install` is not only for CI: without it Rokit
**prompts** before installing a tool it has not seen, and a prompt in the one
command every fresh checkout runs is a command that hangs an agent forever. The
trust boundary is the committed `rokit.toml`.

**The `awk` filter on `typecheck` is the most important line in this profile.**
`luau-lsp analyze` does not fail when it cannot understand its inputs - it
degrades and says so on stdout. Measured, luau-lsp 1.69.0, with `src` entirely
intact:

| given | prints | exits |
|---|---|---|
| `--sourcemap` at a file that does not exist | `[ERROR] Failed to load ... for workspace 'CLI'` | **0** |
| `--sourcemap` at JSON it cannot parse | `Sourcemap parsing failed, sourcemap is not loaded` | **0** |
| `--definitions` at a file that does not exist | `[ERROR] Failed to read definitions file ... Extended types will not be provided` | **0** |

In every one it carries on with no DataModel and/or no Roblox types, resolves
almost nothing, finds nothing wrong, and exits 0. **The file count cannot see
this** - the files are all there and all counted. The `awk` pass prints every
line through unchanged and exits 1 if it saw either shape. A real `TypeError`
line does not match the pattern, so the two are never confused.

`rojo sourcemap` is **not a gate**. It is a prerequisite step that produces the
file `luau-lsp` needs to resolve `script.Parent` style references to real paths,
so it is chained into `typecheck` with `&&`. `sourcemap.json` is generated and
belongs in `.gitignore` — which is also what makes the phase lock classify it as
`ignored` rather than as frozen source. Worth knowing: with `src` emptied,
`rojo sourcemap` still **exits 0** and writes a sourcemap that makes `luau-lsp`
print "Sourcemap parsing failed" and carry on. Its exit code is not a check.

`globalTypes.d.luau` is the Roblox API type dump, generated rather than authored:

    https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/<version>/scripts/globalTypes.d.luau

**Pin it to the `luau-lsp` version in `rokit.toml`, not to `main`** - the dump
and the analyser move together, and a mismatched dump produces type errors that
look like code errors. Read the version out of the manifest so the two cannot
drift:

    v=$(sed -n 's/^luau-lsp = ".*@\(.*\)"$/\1/p' rokit.toml)

Checked, so nobody re-checks: the luau-lsp **release assets** carry only the four
platform zips and `Luau.rbxm`, no type dump; the per-security-level variants
(`globalTypes.None.d.luau` and friends) are not what `analyze --definitions`
wants for a place build.

`build` verifies the artefact is non-empty in the gate itself and prints the byte
count so `evidence` has something to read. Two corrections from running it:
`mkdir -p build` is required, because `build/` is gitignored and Rojo does **not**
create the output's parent directory (`[ERROR rojo] failed to create file ...
(os error 3)`); and the `test -s` turns out to be defence in depth rather than
the primary check - Rojo 7.7.0 exits 1 loudly on a `$path` that does not exist,
and no way was found to make it exit 0 over a zero-byte place. Keep it, and
exercise its limb directly rather than leaving it an untested branch.

## Evidence of work

    evidence | format    | stylua over [1-9][0-9]* files
    evidence | lint      | selene over [1-9][0-9]* files
    evidence | typecheck | analyze over [1-9][0-9]* files
    evidence | unit      | [1-9][0-9]* passed, [0-9]+ failed
    evidence | build     | built [1-9][0-9]* bytes

    floor    | unit      | 1
    floor    | lint      | 1

The `unit` regex assumes the runner contract in "Testing notes" below. If you
adopt a third-party framework instead, this line is the first thing to change,
and the floor has to be able to read the whole number out of it. Require **both
halves** of `N passed, M failed`: a bare `[1-9][0-9]* passed` can be satisfied by
a stray "3 passed" inside a test name, and the floor then measures that instead.

Raise the `unit` floor to a real number as soon as the suite has one — a floor
of 1 catches a suite that vanished entirely, not one that quietly shrank from
120 tests to 4. That is the failure this stack is most exposed to, because a
hand-rolled runner that fails to `require` a test file can easily skip it
rather than crash. Make the runner crash. See below.

## What the runner can see

    discovery | tests     | . | lune run test -- --list | grep -E '^[1-9][0-9]* tests?' > /dev/null
    discovery | sourcemap | . | rojo sourcemap default.project.json --output sourcemap.json && grep -F '<a real source path>' sourcemap.json > /dev/null

The `--list` mode is a **requirement on the runner you write**, not a flag that
exists by default. It must walk the same tree the real run walks, print the
count and each test name, and run nothing. That makes discovery genuinely
independent of the `unit` gate — which is more than `godot.md` can say, and the
payoff for controlling the runner.

The `sourcemap` line asks **Rojo** whether its mapping reaches a real file on
disk, and it is the only independent check on the degradation table above: a
sourcemap that resolves nothing is invisible to every exit code in the gate.

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

Nothing. This profile used to recommend `slow | build` and that was wrong -
**measure before excluding a gate.** Warm, on a Windows 11 laptop: `format`
219 ms, `lint` 224 ms, `unit` 155 ms, `rojo sourcemap` 698 ms, `luau-lsp
analyze` 2,256 ms, **`rojo build` 125 ms.** The place build is the cheapest
command in the stack, faster than the linter, and excluding it cost RED and
GREEN the one gate that notices a broken `default.project.json`.

One thing deliberately kept in: **`typecheck` stays in the
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
    lune/build.luau    headless place build     OPTIONAL - see below
    lune/analyze.luau  type analysis wrapper    OPTIONAL - see below
    default.project.json   Rojo — committed
    rokit.toml             pinned toolchain — committed
    wally.toml/.lock       packages — both committed
    selene.toml stylua.toml .luaurc   committed

`lune/build.luau` and `lune/analyze.luau` are listed because the `paths.conf`
rules below have to anticipate them, **not because you should write them**. The
`build` and `typecheck` gates invoke `rojo` and `luau-lsp` directly and a wrapper
that nothing calls is dead configuration; `bash scripts/classify.sh` answers for
a path whether or not the file exists, so the rules are correct in advance.
Write one when a gate genuinely needs logic a shell line cannot carry.

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

This section is now a record of what a bootstrap story actually hit, not a list
of intentions. Everything above it has been run.

- **Re-verify on YOUR versions and re-probe every gate.** The findings below are
  from specific builds and several of them are version-dependent. What does not
  change is that a gate never observed to fail is not a gate.
- Pin real versions in `rokit.toml` — whatever is current on the day, recorded
  in `docs/wiki/stack.md`. Do not copy version numbers out of a profile.
- **`rokit add JohnnyMorganz/StyLua` installs the alias `StyLua`, capitalised.**
  Every gate command and `doctor.sh` say `stylua`. That is invisible on Windows
  and a `command not found` on Linux CI. Use `rokit add JohnnyMorganz/StyLua
  stylua` and delete the capitalised entry. Check the alias of every tool whose
  repository name is not already lowercase.
- **Prove the vacuous case fails.** `selene` over an existing but empty directory
  exits 0 with `0 errors`: this is the silent-zero, and the counted evidence is
  the only thing that catches it. `selene` over a *missing* directory exits 1, so
  probe with the directory present and emptied - a probe that deletes the whole
  tree tests the wrong branch.
- **`luau-lsp analyze` is honest about nothing and dishonest about everything.**
  Over an empty target it exits 1 (`error: no files provided`). Over a full
  target with a sourcemap or definitions file it could not load, it degrades to
  resolving nothing, reports zero errors and **exits 0**. The degradation is the
  hazard; see the `awk` filter in "Gate commands" above.
- **Selene's `roblox` standard library is built in** to 0.31.0 - no
  `generate-roblox-std`, no generated `roblox.toml`, no network. Verified both
  ways: `game`/`workspace`/`Instance.new` resolve clean, an undefined global
  still raises `error[undefined_variable]`. Do not add an install step for it.
- Establish where `globalTypes.d.luau` comes from and pin it to the luau-lsp
  version, not to `main`; script it into `task install`, and gitignore it.
- **A `.luaurc` with `"languageMode": "strict"` is load-bearing, and here is how
  to prove it** rather than assuming: a return-type mismatch on an annotated
  function fails under *nonstrict* too, so it is a useless probe. Use nil safety
  - a function declared `-> string` returning `string?` passes silently under
  nonstrict and is a `TypeError` under strict. Flip the `.luaurc` with
  `scripts/mutate.sh` and watch both. Add the `--!strict`-header guard test in a
  later story, where it can have a failing test first.
- CI runs Linux; Studio does not exist there and must not be required by any
  gate. If a gate needs Studio, it is not a gate.
- **The bootstrap story writes source with no test forcing it to exist.** Keep it
  to one trivial pure module with a real test, and resist scaffolding the
  architecture's modules - the injected `Clock` and `Rng` this profile recommends
  belong in the first story that can write a failing test for them, not in the
  one phase where nothing checks.

## Testing notes

**The runner.** There is no single dominant Lune test framework the way `pytest`
or `vitest` dominates. Evaluate what exists at bootstrap, but the default
recommendation is **write the runner** — it is roughly 80 lines, and it converts
this profile's weakest property into its strongest: you control the output
format, so `evidence`, `floor` and `discovery` can be exact rather than scraped.

Verified: 148 lines including a long header, using `@lune/fs`, `@lune/process`
and `@lune/stdio` and nothing else. Lune resolves a **computed** `require` path
relative to the requiring file, which is what makes the walk possible - so a
runner in `lune/` requires a discovered `tests/x/y_test.luau` as
`"../tests/x/y_test"`, extension stripped.

The contract it must satisfy:

- Walks `tests/` recursively for `*_test.luau`, `require`s each one.
- **A file that fails to load is a failure, never a skip.** This is the single
  most important line in the runner. A `require` wrapped in a silent `pcall` is
  how a suite quietly shrinks while staying green. Implement it as a `pcall` that
  **counts the failure** - not one that crashes (you lose the rest of the report)
  and not one that moves on. Two cases the plan will not name and the code will
  meet: a module that returns something that is not a table, and a `*_test.luau`
  file that returns an **empty** table. Both are load failures.
- Prints a final line matching `N passed, M failed` with real counts, and exits
  non-zero if `M > 0` **or if `N == 0`**. Zero tests is a failure, not a pass.
  Worth knowing what the `N == 0` half is really for: with a counted `evidence`
  line the *gate* fails either way, on evidence instead of on exit code. It
  earns its place because **RED, GREEN and `task test` run the runner directly**,
  where no evidence line applies - measured, with `tests/` moved aside and the
  check deleted, `lune run test` exits **0**.
- Supports `--list`: same walk, prints `N tests` and each name, runs nothing.
  `--list` must also exit non-zero on a load failure, or `discovery` reports a
  healthy tree while a file is unloadable.

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
    # Linux — VERIFIED 2026-09-16: this line installs rokit-1.2.0-linux-x86_64
    # on ubuntu-24.04 in .github/workflows/gates.yml. macOS still UNVERIFIED.
    curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash

Verify: `rokit --version`.

**2. The pinned tools.** After `rokit.toml` exists:

    rokit install

That must put `rojo`, `wally`, `selene`, `stylua`, `lune` and `luau-lsp` on
PATH **under exactly those names**, because that is how `project.conf` calls
them and what `scripts/doctor.sh` checks for — **and by default one of them is
not.** `rokit add` names the link after the repository, so
`JohnnyMorganz/StyLua` installs as `StyLua`. On Windows that works, because the
filesystem is case-insensitive; on Linux CI it is `stylua: command not found` in
the `format` gate, discovered at the worst possible moment. Pass the alias
explicitly and delete the capitalised entry:

    rokit add JohnnyMorganz/StyLua stylua

Check the alias of every tool whose repository name is not already lowercase.

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
