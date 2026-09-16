---
id: EPIC-00
title: The toolchain is installed, the gates are real, and an empty place builds
status: done
stories: [BOOT-001]
---

## Goal

The repository stops being a directory of documents and becomes a Roblox project.
Rokit pins the toolchain, Rojo builds a place headlessly, Lune runs a test suite,
and all four static tools have a gate command that has been **observed to fail**
when pointed at nothing. `.claude/harness/project.conf` carries a verified command
for every required gate and `BOOTSTRAPPED=yes`.

This is milestone **M0** in the brief, and its definition of done is unchanged: a
deliberately introduced type error fails the gate suite and nothing else does.

## Why now

Nothing else can start. Every later story's correctness rests on `project.conf`
being right, and every later agent will trust it without re-deriving it — that is
the point of the file.

It matters more on this stack than on most. `stack.md` §2: **every tool in this
ecosystem prints nothing when it is happy, and exits 0 just as quietly when
pointed at a directory that does not exist.** There is no "Checked 47 files" line
anywhere. A bootstrap story that lands with a gate silently checking an empty tree
would poison the whole backlog, and no later story would notice — the gates would
be green the entire time.

`docs/wiki/stack.md` is unverified by construction: nothing in it has been
executed, because the toolchain is not installed on this machine. This epic is
where those commands are run for the first time.

## Done when

An operator can clone the repository, run `bash scripts/doctor.sh` and
`bash scripts/gates.sh`, and get a truthful answer — including a truthful
*failure* when they break something. Specifically:

- `bash scripts/gates.sh` passes on the scaffold, and `--audit` passes.
- Each required gate has been broken on purpose and seen to fail, with both
  outputs pasted into the story's `## Gate probes`.
- `docs/wiki/stack.md` and
  `.claude/skills/stack-profiles/reference/roblox-luau.md` have their
  `# UNVERIFIED` banners **deleted**, with resolved tool versions written in.
- CI runs the gates on push with the toolchain installed.

## Stories

1. **BOOT-001** — `bootstrap`. Rokit manifest, Rojo project, Wally manifest, the
   Lune test runner, Selene/StyLua/`.luaurc` configuration, one real example test,
   every gate command verified and corrected, the vacuous case proven to fail for
   each, `paths.conf` and `project.conf` finished, CI toolchain step added.

## Deliberately not in this epic

- **Any game logic.** No phase machine, no seats, no remotes, no telemetry. The
  scaffold's example test covers a trivial module that exists to prove the runner
  runs; it is not the start of the architecture.
- **Any Wally package.** M0–M2 needs none, and B1 #5 makes a new dependency an
  operator decision.
- **The `coverage` gate.** It stays unconfigured and demoted to optional —
  `stack.md` §4 records why, and what replaces it.
- **A mutation runner.** There is no off-the-shelf one for Luau and writing one is
  a project of its own.
- **Open Cloud deployment.** M6, operator-gated.
- **Any guard test over the source tree** — no-`os.clock` rules, no
  no-`OnServerEvent` rules. Those are real behaviour and get a failing test first,
  in the stories that own them. Putting them in SCAFFOLD would be exactly the
  over-sizing the bootstrap sizing rule warns about.

---

## Closed

Closed 2026-09-16, after `EPIC-01`. The delay is itself the record: M0 was
functionally complete when `BOOT-001` landed, but one done-when clause named a
verification that had not happened yet — *"CI runs the gates on push with the
toolchain installed"* — and the epic was left open rather than closed on a
promise. Four epics' worth of CI runs later it is answered, and the two inline
`UNVERIFIED` markers `BOOT-001` left behind have been resolved against that
evidence rather than deleted.

| Done-when clause | Evidence |
|---|---|
| `bash scripts/gates.sh` passes on the scaffold, and `--audit` passes | `BOOT-001`'s `## Gate results`, and every story since. Latest: all five configured gates PASS, `Manifest audit passed.` |
| Each required gate broken on purpose and seen to fail, both outputs pasted | `BOOT-001`'s `## Gate probes` — `lint`, `typecheck`, `unit` and `build`, each with its failing and its restored output |
| The `# UNVERIFIED` banners deleted, resolved tool versions written in | `docs/wiki/stack.md` and `.claude/skills/stack-profiles/reference/roblox-luau.md` both carry a `Verified 2026-09-15` banner naming Rokit 1.2.0, Rojo 7.7.0, Wally 0.3.2, Lune 0.10.5, Selene 0.31.0, StyLua 2.5.2, luau-lsp 1.69.0 |
| CI runs the gates on push with the toolchain installed | `.github/workflows/gates.yml`, `runs-on: ubuntu-latest`, on `pull_request` and on push to `main`. Latest run at close: `actions/runs/35119329930` — `gates` pass 54s, `boundaries` pass 5s |

### The two inline markers, resolved rather than deleted

`BOOT-001` verified the stack on Windows 11 / Git Bash, which is an honest limit
and was marked as one in two places. Both are now settled by CI logs, not by
assertion:

**1. "Every gate runs on `ubuntu-latest`. UNVERIFIED."** (`stack.md` §4.) The line
said *"the first CI run on `BOOT-001`'s pull request is what settles it."* It did.
Run `35119329930` reports `Image: ubuntu-24.04`, `Show tool versions` prints the
same seven pinned versions the Windows measurements were taken against, and all
five configured gates pass. Now `VERIFIED 2026-09-16`, with the caveat that
survives: every *measurement* in `stack.md` is still Windows, and the timings do
differ — `unit` is faster on the runner than locally (`ROUND-005`).

**2. "# macOS / Linux — UNVERIFIED"** on the Rokit `curl` install line
(`roblox-luau.md`, Prerequisites). Linux is now verified, and by the strongest
kind of evidence — that exact line is what CI runs, and it is not a no-op there:

    ##[group]Run command -v rokit > /dev/null || curl -fsSL https://raw.../install.sh | bash
    [1 / 3] Looking for latest rokit release
    [2 / 3] Downloading 'rokit-1.2.0-linux-x86_64.zip'
    [3 / 3] Running rokit installation

`command -v rokit` finds nothing on a fresh runner, so the `curl` branch is the
one taken on every CI run. **macOS remains genuinely unverified** — no macOS
runner exists in this repository and nobody has run it — and it is still marked
so, in both files. An epic does not close by deleting the thing it could not
check.

### Still deliberately absent, and still correct

Nothing in the "Deliberately not in this epic" list has quietly arrived. The
`coverage` gate is still UNCONFIGURED and optional (`stack.md` §4 says why and
what replaces it — on this stack the `unit` floor is what notices a shrinking
suite, and it is now 175). There is still no mutation runner, so
`scripts/mutate.sh` plus a story's predicted mutation table is what stands in for
one; `ROUND-005` is the worked example. No Wally package has been added.

**One defect found while closing, not fixed here.** The `format` and `lint`
evidence counters count `git ls-files` — tracked files — while `stylua` and
`selene` walk the directory, so the number under-reports by exactly a story's own
new files until they are committed (34 vs 38 in `ROUND-005`; 30 vs 34 in
`ROUND-004`). Harmless against a floor of 1, but it makes a liveness assertion
weaker than it reads, and this epic exists precisely because *"exit 0 is not
proof of work."* It belongs in a `HARNESS-*` story.
