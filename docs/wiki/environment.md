# Environment

What has to exist on a machine before `bash scripts/gates.sh` can run, and how
to get it there.

**The good news about this stack:** exactly **one** thing is installed at the
machine level. Every other tool is pinned in a committed `rokit.toml` and
installed into the project by Rokit, so CI and a developer's machine agree by
construction. And **no Roblox account, no Roblox Studio and no credentials are
needed for any gate** — that is the defining property of this toolchain and it
should stay true. Studio becomes necessary only for playtest verification at M3.

## Status, as of 2026-09-15

| | |
|---|---|
| Rokit | **installed**, 1.2.0, verified |
| Everything else | **not installed** — `rokit.toml` does not exist yet; `BOOT-001` creates it |
| Gate commands | **never executed.** See `docs/wiki/stack.md` §1 |

`bash scripts/doctor.sh` is the live answer; this file is the instructions.

## Required

| Tool | Version | Needed for | Installed by |
|---|---|---|---|
| `rokit` | 1.2.0 | `task install`; bootstrapping everything below | **you**, once, per machine |
| `rojo` | pinned by `BOOT-001` | gate `typecheck` (sourcemap), gate `build`, `task dev` | `rokit install` |
| `lune` | pinned by `BOOT-001` | gate `unit`, `task test` | `rokit install` |
| `selene` | pinned by `BOOT-001` | gate `lint` | `rokit install` |
| `stylua` | pinned by `BOOT-001` | gate `format` | `rokit install` |
| `luau-lsp` | pinned by `BOOT-001` | gate `typecheck`, `task analyze` | `rokit install` |
| `wally` | pinned by `BOOT-001` | `task deps`, `task install` | `rokit install` |
| `git` | any recent | the harness itself; every gate counts its inputs with `git ls-files` | already present |

`scripts/doctor.sh` checks for each of these **by the exact name above**, because
that is how `.claude/harness/project.conf` invokes them.

## Install

### 1. Rokit — the only machine-level install

    # Windows — verified 2026-09-15 on Windows 11, returned Rokit 1.2.0
    winget install --id Rojo.Rokit

    # macOS / Linux — UNVERIFIED, not run on this machine
    curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash

Then create Rokit's shim directory and put it on PATH:

    rokit self-install

Verify: `rokit --version` prints `rokit 1.2.0`.

### 2. The pinned tools

Requires `rokit.toml`, which does not exist yet — **`BOOT-001` creates it** by
running `rokit add` per tool so that Rokit resolves current releases rather than
anyone inventing version numbers. Once it exists:

    rokit install

Verify each: `rojo --version`, `lune --version`, `selene --version`,
`stylua --version`, `luau-lsp --version`, `wally --version`.

### 3. Project dependencies

    wally install

Populates `Packages/`, which is gitignored vendor output. `wally.lock` is
committed.

## Notes

**PATH after installing Rokit — measured 2026-09-15, Windows 11, Git Bash.**
`winget install --id Rojo.Rokit` followed by `rokit self-install` puts
`C:\Users\<you>\.rokit\bin` on the **persisted user PATH**, confirmed by reading
`[Environment]::GetEnvironmentVariable("Path","User")`. New shells pick it up.
**Shells already open when you installed do not** — their environment was copied
at launch. In an already-open bash session:

    export PATH="$HOME/.rokit/bin:$PATH"

That is what happened here: `command -v rokit` failed in a bash session started
before the install while `rokit --version` worked in a fresh PowerShell. It is a
stale-environment symptom, not a broken install. Opening a new terminal is the
real fix.

**`globalTypes.d.luau` and `sourcemap.json` are generated, not installed.**
`sourcemap.json` comes from `rojo sourcemap`, chained into the `typecheck` gate.
`globalTypes.d.luau` is the Roblox API type dump that `luau-lsp` needs; where it
is fetched from is `BOOT-001`'s job to establish and pin. Both are gitignored, and
both are classified `vendor` in `paths.conf` so the phase lock never freezes
them. A stale type dump produces type errors that look like code errors.

**The harness self-test is slow on Windows and that is not a hang.**
`bash scripts/selftest.sh` takes 10–25 minutes here — measured runs of 607s,
1133s and 1423s on the same machine — because the suites spawn thousands of short
`git` and `bash` processes, which costs roughly an order of magnitude more on
Windows than on Linux. It prints per-suite progress to stderr so you can watch
it move. On Linux CI it is not painful.

**Studio is Windows/macOS only.** There is no Linux build, which is a second
reason no gate may ever depend on it. If a gate needs Studio, it is not a gate.

## Optional

Nothing. The `coverage`, `integration` and `mutation` gates are unconfigured —
see `docs/wiki/stack.md` §4 for why `coverage` is deliberately absent and what
replaces it. No tool needs installing for any of them.
