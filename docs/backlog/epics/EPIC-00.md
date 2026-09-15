---
id: EPIC-00
title: The toolchain is installed, the gates are real, and an empty place builds
status: todo
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
