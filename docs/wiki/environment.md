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
| Everything else | **installed** by `rokit install` from the committed `rokit.toml` |
| Gate commands | **all executed, and all observed to fail on purpose.** `docs/wiki/stack.md` §5 |

`bash scripts/doctor.sh` reports *"Everything this project needs is installed"*
on this machine as of 2026-09-15.

`bash scripts/doctor.sh` is the live answer; this file is the instructions.

## Required

| Tool | Version | Needed for | Installed by |
|---|---|---|---|
| `rokit` | 1.2.0 | `task install`; bootstrapping everything below | **you**, once, per machine |
| `rojo` | 7.7.0 | gate `typecheck` (sourcemap), gate `build`, `task dev` | `rokit install` |
| `lune` | 0.10.5 | gate `unit`, `task test` | `rokit install` |
| `selene` | 0.31.0 | gate `lint` | `rokit install` |
| `stylua` | 2.5.2 | gate `format` | `rokit install` |
| `luau-lsp` | 1.69.0 | gate `typecheck`, `task analyze` | `rokit install` |
| `wally` | 0.3.2 | `task deps`, `task install` | `rokit install` |
| `git` | any recent | the harness itself; every gate counts its inputs with `git ls-files` | already present |
| `curl` | any recent | `task install` fetches `globalTypes.d.luau` | already present |

`scripts/doctor.sh` checks for each of these **by the exact name above**, because
that is how `.claude/harness/project.conf` invokes them.

**The `stylua` name is a trap worth knowing about.** `rokit add
JohnnyMorganz/StyLua` installs the link as `StyLua`, capitalised as the
repository is. On Windows that works because the filesystem is case-insensitive;
on Linux CI it is a `command not found` in the `format` gate. `rokit.toml`
therefore carries an explicit lowercase alias, added with `rokit add
JohnnyMorganz/StyLua stylua`. If you edit `rokit.toml` by hand, keep it.

## Install

### 1. Rokit — the only machine-level install

    # Windows — verified 2026-09-15 on Windows 11, returned Rokit 1.2.0
    winget install --id Rojo.Rokit

    # macOS / Linux — the script EXISTS and was read (HTTP 200, 5,227 bytes,
    # 2026-09-15) but has not been RUN on this machine. It needs curl, unzip,
    # uname and tr; it downloads the latest release into the CURRENT directory,
    # unzips the binary there, runs `rokit self-install`, and deletes both. It
    # installs the latest Rokit, not a pinned one - `rokit.toml` pins everything
    # else. `.github/workflows/gates.yml` is where this first executes for real.
    curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash

Then create Rokit's shim directory and put it on PATH:

    rokit self-install

Verify: `rokit --version` prints `rokit 1.2.0`.

### 2. Everything else, in one command

    bash scripts/task.sh install

That is `rokit install --no-trust-check`, then `wally install`, then the
`globalTypes.d.luau` type dump pinned to the `luau-lsp` version in `rokit.toml`.
Verified from a stripped tree on 2026-09-15; it ends with
`globalTypes.d.luau for luau-lsp 1.69.0: 806997 bytes`.

`--no-trust-check` is there because Rokit otherwise **prompts** before installing
a tool it has not seen, and a prompt in the one command every fresh checkout runs
is a command that hangs an agent. The trust boundary is the committed
`rokit.toml`.

Verify each: `rojo --version`, `lune --version`, `selene --version`,
`stylua --version`, `luau-lsp --version`, `wally --version` — or just run
`bash scripts/doctor.sh`, which checks them from `project.conf` so it cannot
drift from what the gates actually call.

### 3. Nothing else

`wally.toml` declares no packages, so `Packages/` does not currently exist.
`wally.lock` is committed. `wally install` still runs (it updates the package
index), and `task install` includes it so the step does not rot before the first
real dependency arrives.

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
`globalTypes.d.luau` is the Roblox API type dump that `luau-lsp` needs, fetched
by `task install` from

    https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/<version>/scripts/globalTypes.d.luau

**pinned to the `luau-lsp` version in `rokit.toml`**, not to `main`, because the
dump and the analyser move together. Both files are gitignored and both are
classified `vendor` in `paths.conf` so the phase lock never freezes them.

A stale or missing type dump does not fail loudly. Measured: with
`--definitions` pointing at a file that does not exist, `luau-lsp analyze` prints
`[ERROR] Failed to read definitions file ... Extended types will not be
provided`, carries on with no Roblox types, finds nothing wrong and **exits 0**.
The `typecheck` gate guards against that with a `test -s` before the run and an
`awk` filter after it; see `docs/wiki/stack.md` §2. If you ever see type errors
that look like code errors, re-run `task install` before believing them.

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
