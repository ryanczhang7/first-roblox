#!/usr/bin/env bash
# HARNESS-006 - a gate's file count is what the tool read, not a list beside it.
#
# WHY A SEPARATE SUITE, rather than more cases in gates.test.sh:
#   * gates.test.sh tests scripts/gates.sh - the liveness MACHINERY - against a
#     throwaway fixture whose gate commands are `printf`s. It needs bash, git
#     and coreutils only, and scripts/refresh-harness.sh REPLACES it wholesale
#     from upstream, so cases added there are lost at the next harness refresh.
#   * this suite tests THIS PROJECT's .claude/harness/project.conf against the
#     real tree and the real toolchain. refresh-harness.sh KEEPS a suite
#     upstream does not ship ("KEPT ... upstream does not ship it - yours"), so
#     it survives.
#   * scripts/selftest.sh globs .claude/tests/*.test.sh, so either placement is
#     discovered; only one of them still exists after a refresh.
#
# WHAT IT ASSERTS, and why it is not a copy of the command under test:
#   the gate command AND its evidence regex are parsed out of project.conf the
#   way scripts/gates.sh parses them (`cut -d'|' -f5-`, `-f3-`), and the count
#   is read out of the command's own output by the rule project.conf's header
#   documents - "the first run of digits at or after the start of the first
#   evidence match". So these pin the number a `floor` would be compared
#   against, and they do not dictate the wording of the line carrying it. A
#   test holding its own copy of the command would assert nothing about the
#   file the gates actually read.
#
# HOW "the target narrows" IS EXPRESSED, and why the two halves are one test:
#   a gate's target is narrowed by replacing the FIRST occurrence of the path
#   list in the command text. That is only an honest narrowing if the path list
#   occurs ONCE - which is exactly what AC-3 and AC-5 require ("the two cannot
#   disagree if there is only one"). So each narrowing case is paired with an
#   occurrence-count case, and neither is evidence without the other: with two
#   copies, "first occurrence" could be the counter's copy rather than the
#   tool's, and a gate could satisfy the narrowing case while counting a list
#   the tool never saw.
#
# REQUIRES THE TOOLCHAIN. Unlike every other suite in .claude/tests this one
# shells out to stylua, selene, rojo and luau-lsp, because the counts it pins
# are facts about what those tools read on this tree. CI installs them before
# `scripts/selftest.sh` runs (.github/workflows/gates.yml: "Install the pinned
# toolchain and the Roblox type definitions" precedes "Harness self-test"). A
# missing tool is a hard failure and never a skip - a skipped counter test is
# the vacuous pass this story exists to abolish.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

CONF="$REPO_ROOT/.claude/harness/project.conf"

# The counts this suite pins. They originate in docs/backlog/stories/HARNESS-006.md
# (AC-7, and PO decision 5's re-measured `gates.sh --fast` at the branch point).
#
# THEY ARE SETTLED PER MEASUREMENT, NOT RE-DERIVED PER RUN. Deriving them from
# the tool at run time is what AC-7 exists to detect: a counter compared against
# a number it computed itself asserts nothing. So they are literals - and the
# cost of that is this paragraph.
#
# THEY TRACK THE TREE, SO THEY MOVE WHEN THE TREE GROWS. Every story that adds
# or removes a .luau file under src, tests or lune makes these stale, and 11 of
# this suite's 40 assertions go red until they are re-measured. That is the
# design working: the numbers are a description of a real tree, and a stale one
# is a real disagreement. When you hit it, DO NOT relax the assertions - go back
# to RED, re-measure with the four commands below, record the probe in the
# story's `## Regressions`, and move the literals.
#
# HOW TO RE-MEASURE (run from the repo root, with ~/.rokit/bin on PATH):
#   BASE_FORMAT / BASE_LINT   - the `gate | format` and `gate | lint` commands
#                               from project.conf, unmodified
#   BASE_TYPECHECK            - the `gate | typecheck` command, unmodified
#   NARROW_FORMAT/NARROW_LINT - the same two with `src tests lune` -> `src`
#   NARROW_TYPECHECK          - typecheck with `src` -> `src/shared`
# Read the number out of each command's own evidence line; do not count files
# yourself, for the same reason the suite does not.
#
# LAST MEASURED: MAP-001 (RED), which adds four test files
# (tests/helpers/BlockoutContract.luau, tests/helpers/BlockoutStubs.luau,
# tests/server/blockout_test.luau, tests/server/blockout_controls_test.luau)
# and whose GREEN adds TWO source files, src/server/facility/Blockout.luau and
# src/server/facility/BlockoutBuilder.luau, both under src/server (story
# `## Contract` C-1; the Machines.luau edit is to an existing file).
# SLICE-006's values (200/200/32, narrow 32/32/9) were confirmed on the tree
# before this story's files were added: `gates.sh --fast` observed 200 for
# format and lint and 32 for typecheck. MEASURED on the uncommitted RED tree
# by `git ls-files --cached --others --exclude-standard` over src tests lune:
# 204 .luau files (200 + 4 tests), src still 32, src/shared still 9, and the
# `harness` gate of `bash scripts/gates.sh --fast` read `stylua over 204
# files` and `selene over 204 files`. PREDICTED post-GREEN, which is what is
# pinned below: 204 + 2 = 206/206/34, narrow 32/32/9 -> 34/34/9 -
# NARROW_TYPECHECK does not move, because both new modules are under
# src/server, not src/shared. THE BASELINES BELOW ARE SET TO THOSE PREDICTED
# GREEN VALUES NOW, IN RED, as VIEW-003, CHAN-004 and the rest did and for the
# same reason: check-boundaries refuses a .claude/tests/** change from any
# other phase (TUNE-001 R-1). The suite is red in RED by design - the "no
# stray .luau files" precondition until the RED commit, and the counters by
# the two source files until GREEN writes them: expected red under `bash
# scripts/gates.sh --fast` on RED's tree is `expected count: 206 / actual
# count: 204` for format and lint, `34 / 32` for typecheck and both narrow src
# cases, `207 / 205` and `35 / 33` for the untracked-file cases, with the
# narrow typecheck (9) not failing. GREEN confirms, never edits; a third
# source file, or one under src/shared/, is a counter failure GREEN cannot fix.
# BEFORE THAT: PROC-001 (RED), which added three test files
# (tests/helpers/TurnContract.luau, tests/server/procedure_test.luau,
# procedure_controls_test.luau) and no source: 119/119/23 -> 122/122/23,
# narrow format/lint unchanged at 23, NARROW_TYPECHECK unchanged at 8. GEN-004's
# predicted GREEN values (119/119/23) were confirmed on the tree before this
# story's files were added: `git ls-files` over src tests lune counted 119
# .luau files and src alone 23. GREEN adds ONE source file,
# src/server/procedure/Procedure.luau, and will move these again:
# 122/122/23 -> 123/123/24, narrow 23 -> 24, NARROW_TYPECHECK unchanged at 8
# (src/server, not src/shared). THE BASELINES BELOW ARE SET TO THOSE PREDICTED
# GREEN VALUES NOW, IN RED, as GEN-001..GEN-004 did and for the same reason:
# check-boundaries refuses a .claude/tests/** change from any other phase
# (TUNE-001 R-1). This suite is red until GREEN adds the file; GREEN confirms,
# never edits. Expected red under `bash scripts/gates.sh --fast` on RED's tree:
# `expected count: 123 / actual count: 122` for format and lint, `24 / 23` for
# typecheck, `124 / 123` and `25 / 24` for the untracked-file cases, and the
# narrow cases `24 / 23`.
# BEFORE THAT: GEN-004 (RED), which added five test files
# (tests/helpers/FacilityContract.luau, FacilityStubs.luau,
# tests/server/par_test.luau, generator_test.luau, facility_controls_test.luau)
# and no source: 112/112/21 -> 117/117/21, narrow format/lint unchanged at
# 21, NARROW_TYPECHECK unchanged at 8. Read from this suite's own failure
# lines under the `harness` gate of `bash scripts/gates.sh --fast` on the
# uncommitted tree, with the baselines below already set to the predicted
# values: `expected count: 119 / actual count: 117` for format and lint,
# `expected count: 23 / actual count: 21` for typecheck, `120 / 118` and
# `24 / 22` for the untracked-file cases, and the narrow cases `23 / 21`,
# which is the measurement that src did not move. GREEN adds TWO source
# files, src/server/facility/Par.luau and Generator.luau, and will move these
# again: 117/117/21 -> 119/119/23, narrow 21 -> 23, NARROW_TYPECHECK unchanged
# at 8 (src/server, not src/shared). THE BASELINES BELOW ARE SET TO THOSE
# PREDICTED GREEN VALUES NOW, IN RED, as GEN-001..GEN-003 did and for the same
# reason: check-boundaries refuses a .claude/tests/** change from any other
# phase (TUNE-001 R-1). This suite is red until GREEN adds both files; GREEN
# confirms, never edits.
# BEFORE THAT: GEN-003 (RED), which added four test files
# (tests/helpers/ProcedureContract.luau, ProcedureStubs.luau,
# tests/server/steps_test.luau, steps_controls_test.luau) and no source:
# 107/107/20 -> 111/111/20, narrow format/lint unchanged at 20, NARROW_TYPECHECK
# unchanged at 8. Read from this suite's own failure lines, run directly with
# `bash .claude/tests/project-counters.test.sh` on the uncommitted tree:
# `expected count: 107 / actual count: 111` for format and lint, `108 / 112`
# for the untracked-file cases, with typecheck and the narrow cases not
# failing, which is the measurement that src did not move. GREEN adds one
# source file, src/server/facility/Steps.luau, and will move these again:
# 111/111/20 -> 112/112/21, narrow 20 -> 21, NARROW_TYPECHECK unchanged at 8
# (src/server, not src/shared). THE BASELINES BELOW ARE SET TO THOSE PREDICTED
# GREEN VALUES NOW, IN RED, as GEN-001 and GEN-002 did and for the same reason:
# check-boundaries refuses a .claude/tests/** change from any other phase
# (TUNE-001 R-1). This suite is red until GREEN adds the file; GREEN confirms,
# never edits.
# BEFORE THAT: GEN-002 (RED), which added four test files
# (tests/helpers/PlacementContract.luau, PlacementStubs.luau,
# tests/server/machines_test.luau, machines_controls_test.luau) and no source:
# 102/102/19 -> 106/106/19, narrow format/lint unchanged at 19, NARROW_TYPECHECK
# unchanged at 8. Read from this suite's own failure lines, run directly with
# `bash .claude/tests/project-counters.test.sh` on the uncommitted tree:
# `expected count: 102 / actual count: 106` for format and lint, `103 / 107`
# for the untracked-file cases, with typecheck and the narrow cases not
# failing, which is the measurement that src did not move. GREEN adds one
# source file, src/server/facility/Machines.luau, and will move these again:
# 106/106/19 -> 107/107/20, narrow 19 -> 20, NARROW_TYPECHECK unchanged at 8
# (src/server, not src/shared). THE BASELINES BELOW ARE SET TO THOSE PREDICTED
# GREEN VALUES NOW, IN RED, as GEN-001 did and for the same reason:
# check-boundaries refuses a .claude/tests/** change from any other phase
# (TUNE-001 R-1). This suite is red until GREEN adds the file; GREEN confirms,
# never edits.
# BEFORE THAT: GEN-001 (RED), which added four test files
# (tests/helpers/LayoutContract.luau, LayoutStubs.luau,
# tests/server/layout_test.luau, layout_controls_test.luau) and no source:
# 97/97/18 -> 101/101/18, narrow format/lint unchanged at 18, NARROW_TYPECHECK
# unchanged at 8. Read from this suite's own failure lines, run directly with
# `bash .claude/tests/project-counters.test.sh` on the uncommitted tree:
# `expected count: 97 / actual count: 101` for format and lint, `98 / 102` for
# the untracked-file cases, with typecheck and the narrow cases not failing,
# which is the measurement that src did not move. GREEN adds one source file,
# src/server/facility/Layout.luau, and will move these again: 101/101/18 ->
# 102/102/19, narrow 18 -> 19, NARROW_TYPECHECK unchanged at 8 (it reads
# src/shared; Layout is in src/server). THE BASELINES BELOW ARE SET TO THOSE
# PREDICTED GREEN VALUES NOW, IN RED, because check-boundaries refuses a
# .claude/tests/** change from any other phase (TUNE-001 R-1). This suite is
# red until GREEN adds the file; GREEN confirms, never edits.
# BEFORE THAT: TUNE-001 (GREEN), which added one source file,
# src/shared/MechanicsTuning.luau: 96/96/17 -> 97/97/18, narrow format/lint
# 17 -> 18, NARROW_TYPECHECK 7 -> 8 (src/shared) - RED's prediction, now
# measured. Read from this suite's own failure lines, run directly with
# `bash .claude/tests/project-counters.test.sh` on the uncommitted tree:
# `expected count: 96 / actual count: 97` for format and lint, `17 / 18` for
# typecheck and both narrowed src targets, `7 / 8` for src/shared, and
# `97 / 98`, `18 / 19` for the untracked-file cases.
# BEFORE THAT: TUNE-001 (RED), which added four test files
# (tests/helpers/MechanicsTuningSpec.luau, MechanicsTuningFakes.luau,
# tests/shared/mechanics_tuning_spec_test.luau,
# mechanics_tuning_controls_test.luau) and no source: 92/92/17 -> 96/96/17,
# narrow format/lint unchanged at 17, NARROW_TYPECHECK unchanged at 7. Read
# from this suite's own failure lines under `gates.sh --fast`
# (.claude/state/gate-logs/harness.log) - `expected count: 92 / actual count:
# 96` for format and lint against `stylua over 96 files` and `selene over 96
# files`, `expected count: 93 / actual count: 97` for the untracked-file
# cases - with typecheck and the narrow cases not failing, which is the
# measurement that src did not move. GREEN adds one source file,
# src/shared/MechanicsTuning.luau, and will move these again: 96/96/17 ->
# 97/97/18, narrow 17 -> 18, NARROW_TYPECHECK 7 -> 8 (src/shared).
# BEFORE THAT: HARNESS-022 (RED), which added two test files
# (tests/helpers/GatedFs.luau, tests/shared/gated_fs_test.luau) and no
# source: 90/90/17 -> 92/92/17, narrow format/lint unchanged at 17,
# NARROW_TYPECHECK unchanged at 7. Read from this suite's own failure lines
# under `gates.sh --fast` (.claude/state/gate-logs/harness.log) - `expected
# count: 90 / actual count: 92` for format and lint against `stylua over 92
# files` and `selene over 92 files`, `expected count: 91 / actual count: 93`
# for the untracked-file cases - with typecheck and the narrow cases not
# failing, which is the measurement that src did not move.
# BEFORE THAT: HARNESS-011 (SCAFFOLD), which added two test files
# (tests/helpers/Contract.luau, tests/shared/contract_raise_test.luau) and no
# source: 88/88/17 -> 90/90/17, narrow format/lint unchanged at 17,
# NARROW_TYPECHECK unchanged. Read from this suite's own failure lines under
# `gates.sh --fast` - `expected count: 88 / actual count: 90` for format and
# lint - with typecheck not failing, which is the measurement that src did not
# move.
# BEFORE THAT: TEL-003 (GREEN), which added one source file,
# src/net/RejectionReporter.luau: 87/87/16 -> 88/88/17, narrow format/lint
# 16 -> 17, NARROW_TYPECHECK unchanged at 7 (src/net, not src/shared) - RED's
# prediction, confirmed. Read from this suite's own failure lines -
# `expected count: 87 / actual count: 88` for format and lint, `expected
# count: 16 / actual count: 17` for typecheck and both narrowed targets.
# BEFORE THAT: TEL-003 (RED), which added four test files (tests/helpers/
# RejectionContract.luau, RejectionStubs.luau, tests/net/rejection_test.luau,
# rejection_controls_test.luau) and no source: 83/83/16 -> 87/87/16. Read from
# this suite's own failure lines under `gates.sh --fast` - `expected count: 83 /
# actual count: 87` for format and lint - with typecheck not failing, which is
# the measurement that src did not move. GREEN adds one source file,
# src/net/RejectionReporter.luau, and moves these again: 87/87/16 -> 88/88/17,
# narrow 16 -> 17, NARROW_TYPECHECK unchanged (src/net, not src/shared).
# BEFORE THAT: TEL-002 (RED), which added four test files (tests/helpers/
# TelemetryEmitContract.luau, TelemetryEmitStubs.luau, tests/server/
# telemetry_emit_test.luau, telemetry_emit_controls_test.luau): 79/79/16 ->
# 83/83/16. Read from this suite's own failure lines - `expected count: 79 /
# actual count: 83` for format and lint - with typecheck not failing, which is
# the measurement that src did not move.
# BEFORE THAT: NET-003 (GREEN), which added one source file,
# src/net/RateLimiter.luau, on top of the six test files its own RED added:
# 78/78/15 -> 79/79/16, narrow format/lint 15 -> 16, NARROW_TYPECHECK
# unchanged at 7 because src/shared gained nothing. Read from this suite's own
# failure lines - `expected count: 78 / actual count: 79` against
# `stylua over 79 files`, and `expected count: 15 / actual count: 16` against
# `analyze over 16 files` - not counted by hand. The narrow typecheck assertion
# did NOT fail, which is the measurement that it did not move.
# BEFORE THAT: NET-003 (RED), which added six test files (tests/helpers/
# RateContract.luau, RateStubs.luau, RateLimitSpec.luau and three
# tests/net/rate_*_test.luau) and no source: 72/72/15 -> 78/78/15, narrow
# unchanged at 15/15/7.
# BEFORE THAT: NET-002 (RED), which added six test files (tests/helpers/
# PhaseContract.luau, PhaseStubs.luau, PhaseUnion.luau and three
# tests/net/phase_*_test.luau) and no source: 66/66/15 -> 72/72/15, narrow
# unchanged at 15/15/7. Read from the harness gate.s own failure lines in
# `gates.sh --fast` - `stylua over 72 files`, `selene over 72 files`,
# `analyze over 15 files` - and the narrow assertions did not move.
# BEFORE THAT: NET-001 (GREEN), which added the story's three production
# modules - src/net/Schema.luau, src/net/Remotes.luau, src/net/Wrapper.luau -
# and no test file: 63/63/12 -> 66/66/15, narrow 12/12/7 -> 15/15/7.
# NARROW_TYPECHECK is unchanged because it is src/shared alone and all three
# modules are src/net. Read from the gates' own commands - `stylua over 66
# files`, `selene over 66 files`, `analyze over 15 files` - and the narrow ones
# from the same commands with the target replaced, as the header prescribes.
# BEFORE THAT: NET-001 (RED), which added seven test files (tests/helpers/
# NetContract.luau, tests/helpers/NetStubs.luau, five tests/net/*_test.luau)
# and ONE probe under src - src/server/__probe_raw_remote.luau, AC-7's negative
# control, classified `test` by paths.conf but a .luau under src to every tool
# here: 55/55/11 -> 63/63/12, narrow 11/11/7 -> 12/12/7. NARROW_TYPECHECK is
# unchanged because it is src/shared alone and the probe is src/server. Read
# from the gates' own evidence lines in `gates.sh --fast` - `stylua over 63
# files`, `selene over 63 files`, `analyze over 12 files` - and the narrow ones
# from the same commands with the target replaced, as the header prescribes.
# BEFORE THAT: TEL-001 (GREEN), which added src/shared/telemetry/Event.luau
# and src/shared/telemetry/Sink.luau and no test file: 53/53/9 -> 55/55/11,
# narrow 9/9/5 -> 11/11/7. Both modules are src/shared, so NARROW_TYPECHECK
# moves this time where SEAT-002's src/server module left it alone. Read from
# the gates' own evidence lines - `stylua over 55 files`, `selene over 55
# files`, `analyze over 11 files` - and the narrow ones from the same commands
# with the target replaced, as the header prescribes.
# BEFORE THAT: TEL-001 (RED), which added five test files (tests/helpers/
# TelemetryContract.luau, tests/helpers/TelemetryStubs.luau and three
# tests/shared/telemetry_*_test.luau) and no source: 48/48/9 -> 53/53/9, narrow
# unchanged at 9/9/5.
# BEFORE THAT: SEAT-002 (GREEN), which added src/server/seats/Projection.luau
# and no test file: 47/47/8 -> 48/48/9, narrow 8/8/5 -> 9/9/5. NARROW_TYPECHECK
# is unchanged because it is src/shared alone and the new module is src/server.
# The numbers were read from the gates' own evidence lines - `stylua over 48
# files`, `selene over 48 files`, `analyze over 9 files` - and the narrow ones
# from the same commands with the target replaced, as the header prescribes.
# BEFORE THAT: SEAT-002 (RED), which added four test files and no source:
# 43/43/8 -> 47/47/8, narrow unchanged at 8/8/5.
# BEFORE THAT: SEAT-001 (return to RED), which added src/server/seats/Ring.luau
# and four test files: 38/38/7 -> 43/43/8, narrow 7/7/5 -> 8/8/5.
# LAST SET: VIEW-003 (RED), which adds four test files
# (tests/helpers/RoundViewContract.luau, RoundViewStubs.luau,
# tests/server/round_view_test.luau, round_view_controls_test.luau) and whose
# GREEN adds ONE source file, src/server/round/RoundView.luau, under
# src/server (story `## Contract` C-2; the Session.luau edit is to an
# existing file). CHAN-004's values (190/190/31, narrow 31/31/9) were
# confirmed on the tree before this story's files were added: `git ls-files
# --cached --others --exclude-standard` over src tests lune counted 190 .luau
# files, src alone 31, src/shared alone 9. MEASURED on the uncommitted RED
# tree by the same command: 194 over src tests lune (190 + 4 tests), src
# still 31, src/shared still 9. PREDICTED post-GREEN, which is what is
# pinned below: 194 + 1 = 195/195/32, narrow 31/31/9 -> 32/32/9 -
# NARROW_TYPECHECK does not move, because the new module is under
# src/server, not src/shared. THE BASELINES BELOW ARE SET TO THOSE PREDICTED
# GREEN VALUES NOW, IN RED, as CHAN-004, CHAN-002, CHAN-005 and VIEW-004 did
# and for the same reason: check-boundaries refuses a .claude/tests/** change
# from any other phase (TUNE-001 R-1). The suite is red in RED by design -
# the "no stray .luau files" precondition until the RED commit, and the
# counters by the one source file until GREEN writes it: expected red under
# `bash scripts/gates.sh --fast` on RED's tree is `expected count: 195 /
# actual count: 194` for format and lint, `32 / 31` for typecheck and both
# narrow src cases, `196 / 195` and `33 / 32` for the untracked-file cases,
# with the narrow typecheck (9) not failing. GREEN confirms, never edits; a
# second source file, or one under src/shared/, is a counter failure GREEN
# cannot fix.
# BEFORE THAT: CHAN-004 (RED), which adds seven test files
# (tests/helpers/PresetRemoteContract.luau, PresetSendsContract.luau,
# PresetSendsStubs.luau, tests/net/preset_remote_test.luau,
# preset_remote_controls_test.luau, tests/server/preset_sends_test.luau,
# preset_sends_controls_test.luau) and whose GREEN adds ONE source file,
# src/server/channel/PresetSends.luau, under src/server (story `## Contract`;
# `SendPreset` goes into the existing src/net/GameRemotes.luau, no new file).
# CHAN-002's values (182/182/30, narrow 30/30/9) were confirmed on the tree
# before this story's files were added: `git ls-files` over src tests lune
# counted 182 .luau files, src alone 30, src/shared alone 9. MEASURED on the
# uncommitted RED tree with `bash scripts/gates.sh --fast`: `stylua over 189
# files`, `selene over 189 files`, `analyze over 30 files` (182 + 7 tests).
# PREDICTED post-GREEN, which is what is pinned below: 189 + 1 = 190/190/31,
# narrow 30/30/9 -> 31/31/9 - NARROW_TYPECHECK does not move, because the new
# module is under src/server, not src/shared. THE BASELINES BELOW ARE SET TO
# THOSE PREDICTED GREEN VALUES NOW, IN RED, as CHAN-002, CHAN-005 and VIEW-004
# did and for the same reason: check-boundaries refuses a .claude/tests/**
# change from any other phase (TUNE-001 R-1). The suite is red in RED by
# design - the "no stray .luau files" precondition until the RED commit, and
# the counters by the one source file until GREEN writes it: expected red
# under `bash scripts/gates.sh --fast` on RED's tree is `expected count: 190 /
# actual count: 189` for format and lint, `31 / 30` for typecheck and both
# narrow src cases, `191 / 190` and `32 / 31` for the untracked-file cases,
# with the narrow typecheck (9) not failing. GREEN confirms, never edits; a
# second source file, or one under src/shared/, is a counter failure GREEN
# cannot fix.
# BEFORE THAT: CHAN-002 (RED), which adds five test files
# (tests/helpers/PresetSpec.luau, PresetContract.luau, PresetStubs.luau,
# tests/shared/presets_test.luau, presets_controls_test.luau) and whose GREEN
# adds ONE source file, src/shared/channel/Presets.luau, under src/shared
# (story `## Contract` P-6). CHAN-006's values (176/176/29, narrow 29/29/8)
# were confirmed on the tree before this story's files were added: `git
# ls-files` over src tests lune counted 176 .luau files, src alone 29,
# src/shared alone 8. MEASURED on the uncommitted RED tree with `bash
# scripts/gates.sh --fast`: `stylua over 181 files`, `selene over 181 files`,
# `analyze over 29 files` (176 + 5 tests). PREDICTED post-GREEN, which is what
# is pinned below: 181 + 1 = 182/182/30, narrow 29/29/8 -> 30/30/9 - this
# time NARROW_TYPECHECK moves too, because the new module is under
# src/shared/. THE BASELINES BELOW ARE SET TO THOSE PREDICTED GREEN VALUES
# NOW, IN RED, as CHAN-005 and VIEW-004 did and for the same reason:
# check-boundaries refuses a .claude/tests/** change from any other phase
# (TUNE-001 R-1). The suite is red in RED by design - the "no stray .luau
# files" precondition until the RED commit, and the counters by the one
# source file until GREEN writes it: expected red under `bash scripts/gates.sh
# --fast` on RED's tree is `expected count: 182 / actual count: 181` for
# format and lint, `30 / 29` for typecheck and both narrow src cases, `9 / 8`
# for the narrow typecheck, `183 / 182` and `31 / 30` for the untracked-file
# cases. GREEN confirms, never edits; a second source file, or one outside
# src/shared/, is a counter failure GREEN cannot fix.
# BEFORE THAT: CHAN-006 (RED), which adds four test files
# (tests/helpers/PingLifecycleContract.luau, PingLifecycleStubs.luau,
# tests/server/ping_lifecycle_test.luau, ping_lifecycle_controls_test.luau)
# and NO source: GREEN extends src/server/channel/Pings.luau in place and
# adds no file. CHAN-005's predicted GREEN values (172/172/29) were
# confirmed on the tree before this story's files were added: `git ls-files`
# over src tests lune counted 172 .luau files and src alone 29. MEASURED on
# the uncommitted RED tree with `bash scripts/gates.sh --fast`: `stylua over
# 176 files`, `selene over 176 files`, `analyze over 29 files` (172 + 4
# tests). These are also the post-GREEN counts: 176/176/29, narrow unchanged
# at 29/29/8. The "no stray .luau files" precondition is the one red line in
# RED and clears at the RED commit. GREEN confirms, never edits; a new source
# file is a counter failure GREEN cannot fix.
# BEFORE THAT: CHAN-005 (RED), which adds seven test files
# (tests/helpers/PingRemoteContract.luau, PingsContract.luau, PingsStubs.luau,
# tests/net/ping_remote_test.luau, ping_remote_controls_test.luau,
# tests/server/pings_test.luau, pings_controls_test.luau) and whose GREEN adds
# ONE source file, src/server/channel/Pings.luau (GameRemotes.luau is edited
# in place). CHAN-003's values (164/164/28) were confirmed on the tree before
# this story's files were added: `git ls-files` over src tests lune counted
# 164 .luau files and src alone 28. MEASURED on the uncommitted RED tree with
# `bash scripts/gates.sh --fast`: `stylua over 171 files`, `selene over 171
# files`, `analyze over 28 files` (164 + 7 tests). PREDICTED post-GREEN, which
# is what is pinned below: 171 + 1 = 172/172/29, narrow 28/28/8 -> 29/29/8
# (the new module is under src/server/, not src/shared/, so NARROW_TYPECHECK
# does not move). THE BASELINES BELOW ARE SET TO THOSE PREDICTED GREEN VALUES
# NOW, IN RED, as VIEW-004 and SLICE-003 did and for the same reason:
# check-boundaries refuses a .claude/tests/** change from any other phase
# (TUNE-001 R-1). The suite is red in RED by design - the "no stray .luau
# files" precondition until the RED commit, and AC-7 by the one source file
# until GREEN writes it: expected red under `bash scripts/gates.sh --fast` on
# RED's tree is `expected count: 172 / actual count: 171` for format and lint,
# `29 / 28` for typecheck and both narrow src cases, `173 / 172` and `30 / 29`
# for the untracked-file cases. GREEN confirms, never edits; a second source
# file, or one under src/shared/, is a counter failure GREEN cannot fix.
# BEFORE THAT: CHAN-003 (RED), which adds four test files
# (tests/helpers/DeclineContract.luau, DeclineStubs.luau,
# tests/net/decline_test.luau, decline_controls_test.luau) and NO source:
# GREEN edits src/net/Wrapper.luau, RateLimiter.luau, Remotes.luau and
# RejectionReporter.luau in place and adds no file. VIEW-004's predicted
# GREEN values (160/160/28) were confirmed on the tree before this story's
# files were added: `git ls-files` over src tests lune counted 160 .luau
# files and src alone 28. MEASURED on the uncommitted RED tree with the gate
# commands out of project.conf: `stylua over 164 files`, `selene over 164
# files`, `analyze over 28 files` (160 + 4 tests). These are also the
# post-GREEN counts: 164/164/28, narrow unchanged at 28/28/8. The "no stray
# .luau files" precondition is the one red line in RED and clears at the RED
# commit. GREEN confirms, never edits; a new source file is a counter
# failure GREEN cannot fix.
# BEFORE THAT: VIEW-004 (RED), which adds six test files
# (tests/helpers/PositionsContract.luau, PositionsStubs.luau,
# SessionRoundStubs.luau, tests/server/positions_test.luau,
# positions_controls_test.luau, session_positions_test.luau) and whose GREEN
# adds ONE source file, src/server/session/Positions.luau. MEASURED on the
# uncommitted RED tree with the gate commands out of project.conf: `stylua
# over 159 files`, `selene over 159 files`, `analyze over 27 files` (153 + 6
# tests). PREDICTED post-GREEN, which is what is pinned below: 159 + 1 =
# 160/160/28, narrow 27/27/8 -> 28/28/8 (the new module is under
# src/server/, not src/shared/, so NARROW_TYPECHECK does not move). THE
# BASELINES BELOW ARE SET TO THOSE PREDICTED GREEN VALUES NOW, IN RED, as
# SLICE-003 and PROC-005 did and for the same reason: check-boundaries
# refuses a .claude/tests/** change from any other phase (TUNE-001 R-1). The
# suite is red in RED by design - the "no stray .luau files" precondition
# until the RED commit, and AC-7 by the one source file until GREEN writes
# it: expected red under `bash scripts/gates.sh --fast` on RED's tree is
# `expected count: 160 / actual count: 159` for format and lint, `28 / 27`
# for typecheck and both narrow src cases, `161 / 160` and `29 / 28` for the
# untracked-file cases. GREEN confirms, never edits; a second source file, or
# one under src/shared/, is a counter failure GREEN cannot fix.
# BEFORE THAT: VIEW-002 (RED), which adds four test files
# (tests/helpers/TurnCuesContract.luau, tests/helpers/TurnCuesStubs.luau,
# tests/server/turn_cues_test.luau, tests/server/turn_cues_controls_test.luau)
# and no source: GREEN extends src/server/seats/Projection.luau only. MEASURED
# on the uncommitted RED tree with `bash scripts/gates.sh --fast`: `stylua over
# 153 files`, `selene over 153 files`, `analyze over 27 files`. These are also
# the post-GREEN counts: 149 + 4 = 153/153/27, narrow unchanged at 27/27/8.
# The "no stray .luau files" precondition is red until the RED commit.
# BEFORE THAT: VIEW-001 (RED), which adds four test files
# (tests/helpers/LensViewContract.luau, tests/helpers/LensViewStubs.luau,
# tests/server/lens_view_test.luau, tests/server/lens_view_controls_test.luau)
# and no source: GREEN extends src/server/seats/Projection.luau and edits one
# comment line of src/server/seats/Ring.luau. MEASURED on the uncommitted RED
# tree with `bash scripts/gates.sh --fast`: `stylua over 149 files`, `selene
# over 149 files`, `analyze over 27 files`. These are also the post-GREEN
# counts: 145 + 4 = 149/149/27, narrow unchanged at 27/27/8. The "no stray
# .luau files" precondition is red until the RED commit.
# BEFORE THAT: SLICE-005 (RED), which adds four test files
# (tests/helpers/ScriptedRound.luau, tests/helpers/SessionRoundContract.luau,
# tests/server/session_round_test.luau, tests/server/session_round_controls_test.luau)
# and no source: GREEN extends src/server/session/Session.luau only. MEASURED
# on the uncommitted RED tree with `bash scripts/gates.sh --fast`: `stylua over
# 145 files`, `selene over 145 files`, `analyze over 27 files`. These are also
# the post-GREEN counts: 141 + 4 = 145/145/27, narrow unchanged at 27/27/8.
# The "no stray .luau files" precondition is red until the RED commit.
# BEFORE THAT: SLICE-003 (RED), which adds three test files
# (tests/helpers/SessionContract.luau, tests/server/session_test.luau,
# tests/server/session_controls_test.luau) and whose GREEN adds ONE source
# file, src/server/session/Session.luau. MEASURED on the uncommitted RED tree
# with the gate commands out of project.conf: `stylua over 140 files`,
# `selene over 140 files`, and 26 .luau files under src by the typecheck
# gate's own derived count (137 + 3 tests; PROC-005's predicted 137/137/26
# confirmed before this story's files were added). PREDICTED post-GREEN,
# which is what is pinned below: 140 + 1 = 141/141/27, narrow 26/26/8 ->
# 27/27/8 (the new module is under src/server/, not src/shared/, so
# NARROW_TYPECHECK does not move). The suite is red in RED by design - the
# "no stray .luau files" precondition until the RED commit, and AC-7 by the
# one source file until GREEN writes it: expected red under
# `bash scripts/gates.sh --fast` on RED's tree is `expected count: 141 /
# actual count: 140` for format and lint, `27 / 26` for typecheck and both
# narrow src cases, `142 / 141` and `28 / 27` for the untracked-file cases.
# GREEN confirms, never edits; a second source file, or one under
# src/shared/, is a counter failure GREEN cannot fix.
# BEFORE THAT: PROC-005 (RED), which added six test files (tests/helpers/
# TurnRemoteContract.luau, tests/helpers/TurnRequestsContract.luau,
# tests/net/turn_remote_test.luau, tests/net/turn_remote_controls_test.luau,
# tests/server/turn_requests_test.luau, tests/server/turn_requests_controls_test.luau)
# and whose GREEN adds TWO source files, src/net/GameRemotes.luau and
# src/server/procedure/TurnRequests.luau. MEASURED on the uncommitted RED tree:
# `stylua over 135 files`, `selene over 135 files`, `analyze over 24 files`
# (129 + 6 tests). PREDICTED post-GREEN, which is what is pinned below:
# 135 + 2 = 137/137/26, narrow 24/24/8 -> 26/26/8 (both new modules are under
# src/, neither under src/shared). The suite is red in RED by design - the
# "no stray .luau files" precondition until the RED commit, and AC-7 by the
# two source files until GREEN writes them. GREEN confirms, never edits.
# BEFORE THAT: PROC-003 (RED), which added three test files
# (tests/helpers/OutcomeContract.luau, tests/server/procedure_outcome_test.luau,
# tests/server/procedure_outcome_controls_test.luau) and no source: 126/126/24
# -> 129/129/24, narrow unchanged at 24/24/8. GREEN edits Procedure.luau only,
# so these are also the post-GREEN counts. Read from `stylua over 129 files`
# and `selene over 129 files` on the uncommitted RED tree (the "no stray .luau
# files" precondition is the one red line there, and clears at the RED commit).
# BEFORE THAT: PROC-002 (RED), which added three test files
# (tests/helpers/FinaleContract.luau, tests/server/procedure_finale_test.luau,
# tests/server/procedure_finale_controls_test.luau) and no source: 123/123/24
# -> 126/126/24, narrow unchanged at 24/24/8. GREEN edits Procedure.luau only,
# so these are also the post-GREEN counts. Read from `stylua over 126 files`
# and `selene over 126 files` on the uncommitted RED tree.
BASE_FORMAT=206    # stylua  over src tests lune   (206 = 34 src + 172 tests/lune: MAP-001 RED adds 4 test files and GREEN two source files, predicted; SLICE-006 read "observed 200")
BASE_LINT=206      # selene  over src tests lune
BASE_TYPECHECK=34  # analyze over src (+ MAP-001's facility/Blockout and facility/BlockoutBuilder, predicted; NET-001 probe included; + SLICE-003's Session; + VIEW-004's Positions; + CHAN-005's Pings; + CHAN-002's Presets; + CHAN-004's PresetSends; + VIEW-003's round/RoundView, predicted)
NARROW_FORMAT=34   # stylua  over src alone (MAP-001 predicted)
NARROW_LINT=34     # selene  over src alone (MAP-001 predicted)
NARROW_TYPECHECK=9 # analyze over src/shared alone (moved by TUNE-001's MechanicsTuning; + CHAN-002's channel/Presets; VIEW-003 adds nothing under src/shared)

# Scratch files. Named `__probe_*` so paths.conf classifies them as `test`
# rather than `source` - rules.md's probe convention - and so every guard that
# walks the tree skips them.
UNTRACKED_REL="src/shared/__probe_h006_untracked.luau"
UNFORMATTED_REL="src/shared/__probe_h006_unformatted.luau"
IGNORED_REL="src/build/__probe_h006_ignored.luau"
UNTRACKED="$REPO_ROOT/$UNTRACKED_REL"
UNFORMATTED="$REPO_ROOT/$UNFORMATTED_REL"
IGNORED="$REPO_ROOT/$IGNORED_REL"
IGNORED_DIR="$REPO_ROOT/src/build"

cleanup() {
  rm -f "$UNTRACKED" "$UNFORMATTED" "$IGNORED"
  rmdir "$IGNORED_DIR" 2>/dev/null
  return 0
}
trap cleanup EXIT

# --- reading project.conf the way gates.sh reads it --------------------------

# Pure bash, and deliberately so: project.conf is ~400 lines and this runs once
# per gate, so a `sed` or a `cut` per line is 12,000 process spawns - which on
# Windows is minutes. It sets TRIMMED rather than echoing, because a command
# substitution forks too.
_trim_var() { # <text> -> TRIMMED
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  TRIMMED="$s"
}

conf_value() { # <kind> <id> <first field of the value, 1-based> -> the value
  local kind="$1" id="$2" from="$3" line rest n
  while IFS= read -r line; do
    line="${line%$'\r'}"
    _trim_var "$line"
    case "$TRIMMED" in ''|'#'*) continue ;; esac
    case "$line" in *'|'*) ;; *) continue ;; esac
    _trim_var "${line%%|*}"
    [ "$TRIMMED" = "$kind" ] || continue
    rest="${line#*|}"
    _trim_var "${rest%%|*}"
    [ "$TRIMMED" = "$id" ] || continue
    n=$((from - 2))
    while [ "$n" -gt 0 ]; do rest="${rest#*|}"; n=$((n - 1)); done
    _trim_var "$rest"
    printf '%s' "$TRIMMED"
    return 0
  done < "$CONF"
  return 1
}

gate_cmd()      { conf_value gate     "$1" 5; }
gate_evidence() { conf_value evidence "$1" 3; }

# --- running a gate command --------------------------------------------------

# run_conf_cmd <command> [nopipefail]   Sets OUT and RC.
#
# The default mode matches scripts/gates.sh, which has `set -uo pipefail` at the
# top and runs each gate as `( cd "$ROOT/$cwd" && eval "$cmd" )` - a subshell,
# which INHERITS pipefail. `nopipefail` is the stricter mode: it asks whether
# the command carries its own exit status rather than borrowing the runner's
# shell options.
run_conf_cmd() {
  local cmd="$1" mode="${2:-pipefail}"
  OUT="$( cd "$REPO_ROOT" || exit 97
          if [ "$mode" = "nopipefail" ]; then set +o pipefail; else set -o pipefail; fi
          eval "$cmd" 2>&1 )"
  RC=$?
}

# observed <output> <evidence regex>   The count gates.sh would report, by the
# rule in project.conf's header: the first run of digits at or after the start
# of the first evidence match.
observed() {
  printf '%s\n' "$1" | sed -e 's/\r$//' \
    | grep -oE -m1 -- "($2).*" 2>/dev/null | head -1 \
    | grep -oE '[0-9]+' 2>/dev/null | head -1
}

count_occurrences() { # <haystack> <needle>
  local h="$1" n="$2" c=0
  while :; do
    case "$h" in *"$n"*) c=$((c+1)); h="${h#*"$n"}" ;; *) break ;; esac
  done
  printf '%d' "$c"
}

narrowed_cmd() { # <command> <from> <to>   first occurrence only
  printf '%s' "${1/"$2"/"$3"}"
}

# --- assertions --------------------------------------------------------------

_tail() { printf '%s\n' "$1" | tail -6; }

assert_observed() { # <what> <expected> <output> <evidence regex>
  local got; got="$(observed "$3" "$4")"
  if [ "$got" = "$2" ]; then _ok "$1"
  else _bad "$1" "expected count: $2
actual count:   ${got:-<output matched no evidence regex>}
evidence regex: $4
gate output (last 6 lines):
$(_tail "$3")"
  fi
}

assert_zero() { # <what> <rc> <output>
  if [ "$2" -eq 0 ]; then _ok "$1"
  else _bad "$1" "expected exit 0; got $2
gate output (last 6 lines):
$(_tail "$3")"; fi
}

assert_nonzero() { # <what> <rc> <output>
  if [ "$2" -ne 0 ]; then _ok "$1"
  else _bad "$1" "expected a NON-ZERO exit; got 0 - the gate would PASS
gate output (last 6 lines):
$(_tail "$3")"; fi
}

assert_no_evidence() { # <what> <output> <evidence regex>
  if grep -qE -- "$3" <<< "$2"; then
    _bad "$1" "expected the evidence regex NOT to match, so that gates.sh
reports 'ran but produced no evidence of work'
evidence regex: $3
gate output (last 6 lines):
$(_tail "$2")"
  else _ok "$1"; fi
}

assert_narrowed_count() { # <what> <command> <evidence> <from> <to> <expected>
  local cmd="$2" ev="$3" from="$4" to="$5" want="$6" n narrow
  n="$(count_occurrences "$cmd" "$from")"
  if [ "$n" -eq 0 ]; then
    _bad "$1" "the gate command does not contain the target '$from', so it
cannot be narrowed. Either the target was renamed - update this
test and say so in the story - or the gate no longer names one.
command: $cmd"
    return 0
  fi
  narrow="$(narrowed_cmd "$cmd" "$from" "$to")"
  run_conf_cmd "$narrow"
  assert_observed "$1" "$want" "$OUT" "$ev"
}

# --- preconditions -----------------------------------------------------------

describe "preconditions"

missing=""
for t in stylua selene rojo luau-lsp git; do
  command -v "$t" > /dev/null 2>&1 || missing="$missing $t"
done
assert_eq "the pinned toolchain is on PATH" "" "$missing"
if [ -n "$missing" ]; then
  printf '\n  Cannot run the counter tests without%s.\n' "$missing"
  printf '  Put ~/.rokit/bin on PATH, or run: bash scripts/task.sh install\n'
  printf '  This suite is NOT skippable: a skipped counter test is the vacuous\n'
  printf '  pass HARNESS-006 exists to abolish.\n'
  summary "project-counters"
  exit 1
fi

# Fail closed (HARNESS-023): the helper lists every untracked FILE, so a new
# .luau in a new directory is seen, and a helper that is missing or cannot run
# git is a red exit status with its message in $stray, never an empty string.
stray="$(bash "$REPO_ROOT/scripts/stray-luau.sh" "$REPO_ROOT" 2>&1)"; stray_rc=$?
assert_eq "the stray-luau check ran (exit 0)" "0" "$stray_rc"
assert_eq "the working tree carries no stray .luau files, so the baselines mean what they say" "" "$stray"

assert_eq "project.conf declares a format gate command"    "0" "$(gate_cmd format    > /dev/null; printf '%d' $?)"
assert_eq "project.conf declares a lint gate command"      "0" "$(gate_cmd lint      > /dev/null; printf '%d' $?)"
assert_eq "project.conf declares a typecheck gate command" "0" "$(gate_cmd typecheck > /dev/null; printf '%d' $?)"

CMD_FORMAT="$(gate_cmd format)";       EV_FORMAT="$(gate_evidence format)"
CMD_LINT="$(gate_cmd lint)";           EV_LINT="$(gate_evidence lint)"
CMD_TYPECHECK="$(gate_cmd typecheck)"; EV_TYPECHECK="$(gate_evidence typecheck)"

# ---------------------------------------------------------------------------
# AC-7 - the fix corrects WHAT is measured, not the measurement. 47 / 47 / 8,
# the settled literals above rather than a re-derivation. Each also asserts the
# gate's own evidence regex still matches its output, because the count is only
# "the count the gate reports" if gates.sh can find it.
describe "AC-7: the three gates report the settled counts for this tree"

run_conf_cmd "$CMD_FORMAT"
assert_zero     "the format gate passes on the unmodified tree"     "$RC" "$OUT"
assert_observed "format reports 92 files on the unmodified tree"    "$BASE_FORMAT" "$OUT" "$EV_FORMAT"

run_conf_cmd "$CMD_LINT"
assert_zero     "the lint gate passes on the unmodified tree"       "$RC" "$OUT"
assert_observed "lint reports 92 files on the unmodified tree"      "$BASE_LINT" "$OUT" "$EV_LINT"

run_conf_cmd "$CMD_TYPECHECK"
assert_zero     "the typecheck gate passes on the unmodified tree"  "$RC" "$OUT"
assert_observed "typecheck reports 17 files on the unmodified tree"  "$BASE_TYPECHECK" "$OUT" "$EV_TYPECHECK"

# ---------------------------------------------------------------------------
# AC-1 / AC-3 / AC-5, structural half. "The two cannot disagree if there is
# only one." A second copy of the path list IS the defect, and it is also what
# would let the narrowing cases below be satisfied dishonestly.
describe "a gate names its target once, so the tool and the counter cannot disagree"

assert_eq "the format gate names 'src tests lune' exactly once"  "1" "$(count_occurrences "$CMD_FORMAT" 'src tests lune')"
assert_eq "the lint gate names 'src tests lune' exactly once"    "1" "$(count_occurrences "$CMD_LINT" 'src tests lune')"
assert_eq "the typecheck gate names 'src' exactly once"          "1" "$(count_occurrences "$CMD_TYPECHECK" 'src')"

# ---------------------------------------------------------------------------
# NOT an acceptance criterion - a regression guard for an invariant BOOT-001
# established, and one the Contract's own suggested shape would break. It is
# here because nothing else in the repository would notice:
#
#   scripts/doctor.sh line 74: exe=$(printf '%s' "$cmd" | awk '{print $1}')
#
# doctor takes the FIRST TOKEN of every gate command as the tool to look for on
# PATH. A command beginning `T="src tests lune"; selene $T` - which is what the
# Contract suggests for lint and typecheck - makes doctor report a permanently
# MISSING tool called `T="src`. doctor is not a gate, so no gate would fail; the
# only thing that would ever say so is this line. Earned by probe 10.
describe "every gate command starts with a real executable, so doctor.sh can find the tool"

for g in format lint typecheck; do
  case "$g" in
    format)    c="$CMD_FORMAT" ;;
    lint)      c="$CMD_LINT" ;;
    typecheck) c="$CMD_TYPECHECK" ;;
  esac
  exe="$(printf '%s' "$c" | awk '{print $1}')"
  assert_eq "the $g gate's first token ($exe) is on PATH, as scripts/doctor.sh requires" "0" \
    "$(command -v "$exe" > /dev/null 2>&1; printf '%d' $?)"
done

# ---------------------------------------------------------------------------
describe "AC-1: the format count is the number of files stylua read"

assert_narrowed_count "narrowing the format target to src reports 17, not 92" \
  "$CMD_FORMAT" "$EV_FORMAT" 'src tests lune' 'src' "$NARROW_FORMAT"

# The empty boundary, and the BOOT-001 invariant it collides with: every stage
# of a count pipeline must exit 0 on a target with no .luau files, so the gate
# fails as "ran but produced no evidence of work" rather than as an opaque exit
# 1. MEASURED: `stylua --check -v docs | grep -c '^debug: formatted '` prints 0
# and grep EXITS 1, and gates.sh runs gate commands under pipefail.
describe "AC-1, empty boundary: a format target with no .luau files claims no work"

narrow="$(narrowed_cmd "$CMD_FORMAT" 'src tests lune' 'docs')"
run_conf_cmd "$narrow"
assert_zero        "exits 0 on a target with no .luau files, rather than dying on grep's empty count" "$RC" "$OUT"
assert_no_evidence "does not report a count it did not read" "$OUT" "$EV_FORMAT"

# ---------------------------------------------------------------------------
describe "AC-3: the lint count moves with the target selene was handed"

assert_narrowed_count "narrowing the lint target to src reports 17, not 92" \
  "$CMD_LINT" "$EV_LINT" 'src tests lune' 'src' "$NARROW_LINT"

# ---------------------------------------------------------------------------
describe "AC-5: the typecheck count moves with the target luau-lsp was handed"

assert_narrowed_count "narrowing the typecheck target to src/shared reports 5, not 9" \
  "$CMD_TYPECHECK" "$EV_TYPECHECK" 'src' 'src/shared' "$NARROW_TYPECHECK"

# ---------------------------------------------------------------------------
# AC-2 / AC-4 - the ROUND-005 symptom as a test rather than an anecdote: a file
# on disk that git does not yet track is read by every one of these tools, and
# a counter built on bare `git ls-files` cannot see it.
describe "AC-2/AC-4: a .luau file on disk but not yet tracked by git is counted"

printf -- '--!strict\nlocal M = {}\nreturn M\n' > "$UNTRACKED"
assert_eq "the scratch file is untracked (precondition)" "" \
  "$( cd "$REPO_ROOT" && git ls-files -- "$UNTRACKED_REL" )"
assert_eq "the scratch file is not ignored (precondition)" "1" \
  "$( cd "$REPO_ROOT" && git check-ignore -q "$UNTRACKED_REL"; printf '%d' $? )"

run_conf_cmd "$CMD_FORMAT"
assert_zero     "AC-2: the format gate still passes with the untracked file present" "$RC" "$OUT"
assert_observed "AC-2: format counts the untracked file (92 -> 93)" "$((BASE_FORMAT + 1))" "$OUT" "$EV_FORMAT"

run_conf_cmd "$CMD_LINT"
assert_zero     "AC-4: the lint gate still passes with the untracked file present"   "$RC" "$OUT"
assert_observed "AC-4: lint counts the untracked file (92 -> 93)"   "$((BASE_LINT + 1))" "$OUT" "$EV_LINT"

# The Contract applies the same `--cached --others --exclude-standard` rule to
# typecheck; luau-lsp walks src the same way selene walks its target.
run_conf_cmd "$CMD_TYPECHECK"
assert_zero     "the typecheck gate still passes with the untracked file present"    "$RC" "$OUT"
assert_observed "typecheck counts the untracked file (17 -> 18)"      "$((BASE_TYPECHECK + 1))" "$OUT" "$EV_TYPECHECK"

rm -f "$UNTRACKED"

# ---------------------------------------------------------------------------
# AC-6 - this story's own defect pointing the other way. Ignored means
# generated, not authored (rules.md); a counter that swept in build output
# would inflate every gate on this stack, invisibly.
describe "AC-6: a .luau file .gitignore covers is not counted"

mkdir -p "$IGNORED_DIR"
printf -- '--!strict\nlocal M = {}\nreturn M\n' > "$IGNORED"
assert_eq "the scratch file really is ignored (precondition - otherwise this case is vacuous)" "0" \
  "$( cd "$REPO_ROOT" && git check-ignore -q "$IGNORED_REL"; printf '%d' $? )"

run_conf_cmd "$CMD_FORMAT"
assert_zero     "the format gate still passes with an ignored .luau file present"    "$RC" "$OUT"
assert_observed "format does not count the ignored file (still 92)"    "$BASE_FORMAT" "$OUT" "$EV_FORMAT"

run_conf_cmd "$CMD_LINT"
assert_zero     "the lint gate still passes with an ignored .luau file present"      "$RC" "$OUT"
assert_observed "lint does not count the ignored file (still 92)"      "$BASE_LINT" "$OUT" "$EV_LINT"

run_conf_cmd "$CMD_TYPECHECK"
assert_zero     "the typecheck gate still passes with an ignored .luau file present" "$RC" "$OUT"
assert_observed "typecheck does not count the ignored file (still 17)"  "$BASE_TYPECHECK" "$OUT" "$EV_TYPECHECK"

rm -f "$IGNORED"; rmdir "$IGNORED_DIR" 2>/dev/null

# ---------------------------------------------------------------------------
# PO decision 3, and the trap the Contract names. A counter that reads the
# tool's output through a pipe takes the PIPE's exit status. gates.sh happens
# to run gate commands under `set -o pipefail`, so the naive shape survives
# there - but a gate whose correctness is borrowed from the runner's shell
# options is one refactor of gates.sh away from passing on unformatted code,
# which is strictly worse than the bug this story fixes. Both modes are
# asserted: the one the gate actually runs in, and the one that proves the
# command carries its own exit status.
describe "the format gate FAILS on a badly formatted file, however it counts"

printf 'local x   =   1\nreturn x\n' > "$UNFORMATTED"
assert_nonzero "stylua itself rejects the scratch file (precondition)" \
  "$( cd "$REPO_ROOT" && stylua --check "$UNFORMATTED_REL" > /dev/null 2>&1; printf '%d' $? )" \
  "stylua --check $UNFORMATTED_REL"

run_conf_cmd "$CMD_FORMAT"
assert_nonzero "under pipefail, as scripts/gates.sh runs it" "$RC" "$OUT"

run_conf_cmd "$CMD_FORMAT" nopipefail
assert_nonzero "and without pipefail, so the exit status is stylua's and not grep's" "$RC" "$OUT"

rm -f "$UNFORMATTED"

summary "project-counters"
