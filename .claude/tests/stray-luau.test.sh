#!/usr/bin/env bash
# Tests for scripts/stray-luau.sh - the stray-.luau precondition (HARNESS-023).
#
# Two real-tree suites open with a precondition meant to prove the working tree
# carries no uncommitted .luau under src/, tests/ or lune/, so the counter
# baselines they pin describe a committed tree. The pipeline they used,
#
#   git status --porcelain -- src tests lune | grep -E '\.luau$' || true
#
# has two holes. Default `git status` collapses a NEW untracked directory to one
# line naming the directory (`?? src/shared/channel/`), which does not end in
# `.luau`, so a new file in a new directory is never reported. And `|| true`
# swallows a failing git as well as an empty grep, so a directory that is not a
# repository reads as "clean". Both are the needle-cannot-fail case in rules.md.
#
# The detection moves into scripts/stray-luau.sh, and this suite pins it:
#
#   bash scripts/stray-luau.sh <repo-root>
#     stdout: every porcelain line whose path ends in .luau, unchanged
#     exit 0 whether or not anything printed; stderr silent on success
#     exit 2 + `stray-luau: cannot read git status in <root>` on stderr when
#       git status fails or <root> is not a directory
#
# Every fixture is a throwaway repository under one mktemp directory OUTSIDE
# this checkout, removed by the EXIT trap. Nothing here writes under the real
# src/: a transient .luau there collides with a concurrent typecheck gate run
# and with project-counters' baselines.
#
# Needles. Every expected porcelain line is matched as a WHOLE LINE and COUNTED
# (`grep -cxF`), never as a substring: `?? src/shared/channel/` is a prefix of
# the right answer AND is the wrong answer, so a floating match would pass on
# the very defect this story fixes. The "nothing" cases compare the full output
# to "". Every run asserts its exit status and its stderr.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

HELPER="$REPO_ROOT/scripts/stray-luau.sh"

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t harness.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# --- helpers ----------------------------------------------------------------

# make_repo <name>   A committed repository with one .luau in each of the three
# roots, a .gitignore covering src/build/, and nothing else. Echoes its path.
# Commits carry a local identity: CI has none. `git add` on this Windows
# checkout warns about CRLF on stderr; that is discarded here because it is the
# fixture's noise, not the helper's.
make_repo() {
  local d="$WORK/$1"
  mkdir -p "$d/src/shared" "$d/tests" "$d/lune"
  git -C "$d" init -q
  printf 'return 1\n' > "$d/src/shared/A.luau"
  printf 'return 2\n' > "$d/tests/T.luau"
  printf 'return 3\n' > "$d/lune/L.luau"
  printf 'src/build/\n' > "$d/.gitignore"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm fixture >/dev/null 2>&1
  printf '%s' "$d"
}

# run_helper <root>   Runs the helper against <root>; leaves stdout in OUT,
# stderr in ERR and the exit status in RC. stdout and stderr are captured
# SEPARATELY so that "stderr is silent on success" is an assertion about
# stderr, not about whether the caller's 2>&1 happened to merge something.
OUT=""; ERR=""; RC=0
run_helper() {
  OUT="$(bash "$HELPER" "$1" 2>"$WORK/stderr")"; RC=$?
  ERR="$(cat "$WORK/stderr")"
}

# count_line <line> <text>   How many lines of <text> are exactly <line>.
count_line() { printf '%s\n' "$2" | grep -cxF -- "$1"; }

# line_count <text>   Number of lines; 0 for the empty string.
line_count() { if [ -z "$1" ]; then printf '0'; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }

# old_pipeline <root>   The pipeline being replaced, verbatim. Used ONLY to show
# that a fixture reproduces the defect: a fixture the old pipeline reports
# correctly would not be testing the fix.
old_pipeline() { ( cd "$1" && git status --porcelain -- src tests lune 2>/dev/null | grep -E '\.luau$' || true ); }

# ---------------------------------------------------------------------------
describe "the script under test exists"

# Not an AC. One line saying what is missing, rather than leaving it to be
# inferred from `No such file or directory` in every case below.
if [ -f "$HELPER" ]; then _ok "scripts/stray-luau.sh is present"
else _bad "scripts/stray-luau.sh is present" "no such file: $HELPER"; fi

# ---------------------------------------------------------------------------
describe "AC-1: a new .luau inside a NEW directory is reported by its file path, not collapsed to the directory"

FX="$(make_repo ac1-newdir)"
mkdir -p "$FX/src/shared/channel"
printf 'return {}\n' > "$FX/src/shared/channel/Presets.luau"

# Fixture control: the pipeline being replaced sees NOTHING here. Green in RED
# and forever - it pins the fixture, not the helper - and it is what makes DV-1
# mean something: a git whose default stopped collapsing directories would make
# this fixture stop discriminating, and this line would say so.
assert_eq "fixture control: the old pipeline reports nothing for a new file in a new directory (the defect)" \
  "" "$(old_pipeline "$FX")"

run_helper "$FX"
assert_eq "exit 0 when a stray file is found (the caller decides what stray means)" "0" "$RC"
assert_eq "reports exactly the one file, by its path" "?? src/shared/channel/Presets.luau" "$OUT"
assert_eq "the line '?? src/shared/channel/Presets.luau' appears once" "1" "$(count_line '?? src/shared/channel/Presets.luau' "$OUT")"
assert_eq "the collapsed directory line '?? src/shared/channel/' does not appear" "0" "$(count_line '?? src/shared/channel/' "$OUT")"
assert_eq "stderr is silent on success" "" "$ERR"

# ---------------------------------------------------------------------------
describe "AC-1: the same two directories deep, under tests/"

FX="$(make_repo ac1-deeper)"
mkdir -p "$FX/tests/new/deeper"
printf 'return {}\n' > "$FX/tests/new/deeper/X.luau"

assert_eq "fixture control: the old pipeline reports nothing two directories deep" "" "$(old_pipeline "$FX")"

run_helper "$FX"
assert_eq "exit 0" "0" "$RC"
assert_eq "reports exactly tests/new/deeper/X.luau" "?? tests/new/deeper/X.luau" "$OUT"
assert_eq "the collapsed line '?? tests/new/' does not appear" "0" "$(count_line '?? tests/new/' "$OUT")"
assert_eq "the collapsed line '?? tests/new/deeper/' does not appear" "0" "$(count_line '?? tests/new/deeper/' "$OUT")"
assert_eq "stderr is silent on success" "" "$ERR"

# ---------------------------------------------------------------------------
describe "AC-1: the repository's own status.showUntrackedFiles=no does not hide the file"

FX="$(make_repo ac1-config)"
git -C "$FX" config status.showUntrackedFiles no
mkdir -p "$FX/src/shared/channel"
printf 'return {}\n' > "$FX/src/shared/channel/Presets.luau"

assert_eq "fixture control: the config is set in the fixture, not globally" "no" "$(git -C "$FX" config --local status.showUntrackedFiles)"
assert_eq "fixture control: plain git status shows nothing under that config" "" "$(git -C "$FX" status --porcelain -- src tests lune)"

run_helper "$FX"
assert_eq "exit 0" "0" "$RC"
assert_eq "reports the file despite status.showUntrackedFiles=no" "?? src/shared/channel/Presets.luau" "$OUT"
assert_eq "stderr is silent on success" "" "$ERR"

# ---------------------------------------------------------------------------
describe "AC-2: a new .luau directly in an EXISTING directory is still reported (the behaviour that already worked)"

FX="$(make_repo ac2-existing-dir)"
printf 'return {}\n' > "$FX/src/shared/B.luau"

assert_eq "fixture control: the old pipeline already reported this case" "?? src/shared/B.luau" "$(old_pipeline "$FX")"

run_helper "$FX"
assert_eq "exit 0" "0" "$RC"
assert_eq "reports exactly src/shared/B.luau" "?? src/shared/B.luau" "$OUT"
assert_eq "stderr is silent on success" "" "$ERR"

# ---------------------------------------------------------------------------
describe "AC-1/AC-2 together: one new-directory file and one existing-directory file are both reported, one line each"

FX="$(make_repo ac12-many)"
printf 'return {}\n' > "$FX/src/shared/B.luau"
mkdir -p "$FX/src/shared/channel"
printf 'return {}\n' > "$FX/src/shared/channel/Presets.luau"
mkdir -p "$FX/lune/jobs"
printf 'return {}\n' > "$FX/lune/jobs/Build.luau"

run_helper "$FX"
assert_eq "exit 0" "0" "$RC"
assert_eq "three lines, no more" "3" "$(line_count "$OUT")"
assert_eq "'?? src/shared/B.luau' once"                "1" "$(count_line '?? src/shared/B.luau' "$OUT")"
assert_eq "'?? src/shared/channel/Presets.luau' once" "1" "$(count_line '?? src/shared/channel/Presets.luau' "$OUT")"
assert_eq "'?? lune/jobs/Build.luau' once"            "1" "$(count_line '?? lune/jobs/Build.luau' "$OUT")"
assert_eq "no collapsed directory line for src/shared/channel/" "0" "$(count_line '?? src/shared/channel/' "$OUT")"
assert_eq "no collapsed directory line for lune/jobs/"          "0" "$(count_line '?? lune/jobs/' "$OUT")"
assert_eq "stderr is silent on success" "" "$ERR"

# ---------------------------------------------------------------------------
describe "AC-3: a committed, unmodified tree prints nothing and exits 0"

FX="$(make_repo ac3-clean)"
run_helper "$FX"
assert_eq "exit 0 on a clean tree" "0" "$RC"
assert_eq "prints nothing on a clean tree" "" "$OUT"
assert_eq "stderr is silent on success" "" "$ERR"

# ---------------------------------------------------------------------------
describe "AC-3: untracked non-.luau files, an ignored .luau, and a .luau outside the three roots are not stray"

FX="$(make_repo ac3-not-stray)"
printf 'notes\n' > "$FX/src/shared/notes.md"            # non-.luau in an existing dir
mkdir -p "$FX/src/newdir"
printf 'readme\n' > "$FX/src/newdir/readme.txt"          # new dir holding only a non-.luau
mkdir -p "$FX/src/build"
printf 'return {}\n' > "$FX/src/build/Gen.luau"          # .luau covered by .gitignore
mkdir -p "$FX/docs"
printf 'return {}\n' > "$FX/docs/X.luau"                 # .luau outside src/tests/lune

# Fixture controls: each distractor really is present and really is untracked
# or ignored, so a "" below is the helper's filter at work, not an empty tree.
assert_eq "fixture control: git sees the four distractors (all untracked, ignored one listed)" "4" \
  "$(git -C "$FX" status --porcelain --untracked-files=all --ignored -- src docs | grep -c '')"
assert_eq "fixture control: src/build/Gen.luau is ignored" "!! src/build/Gen.luau" \
  "$(git -C "$FX" status --porcelain --untracked-files=all --ignored -- src/build | grep -xF -- '!! src/build/Gen.luau')"

run_helper "$FX"
assert_eq "exit 0" "0" "$RC"
assert_eq "prints nothing: none of the four distractors is a stray .luau under the three roots" "" "$OUT"
assert_eq "stderr is silent on success" "" "$ERR"

# ---------------------------------------------------------------------------
describe "AC-3: a committed .luau that is then modified is reported"

FX="$(make_repo ac3-modified)"
printf 'return 1 -- edited\n' > "$FX/src/shared/A.luau"

run_helper "$FX"
assert_eq "exit 0" "0" "$RC"
assert_eq "reports exactly the modified file, in git's own porcelain form" " M src/shared/A.luau" "$OUT"
assert_eq "stderr is silent on success" "" "$ERR"

# A modified file inside a tree that ALSO carries the new-directory case: both
# lines, the collapsed directory line absent.
FX="$(make_repo ac3-modified-plus-newdir)"
printf 'return 1 -- edited\n' > "$FX/src/shared/A.luau"
mkdir -p "$FX/src/shared/channel"
printf 'return {}\n' > "$FX/src/shared/channel/Presets.luau"
run_helper "$FX"
assert_eq "modified + new-directory file: exactly two lines" "2" "$(line_count "$OUT")"
assert_eq "modified + new-directory file: ' M src/shared/A.luau' once" "1" "$(count_line ' M src/shared/A.luau' "$OUT")"
assert_eq "modified + new-directory file: '?? src/shared/channel/Presets.luau' once" "1" "$(count_line '?? src/shared/channel/Presets.luau' "$OUT")"
assert_eq "modified + new-directory file: no '?? src/shared/channel/' line" "0" "$(count_line '?? src/shared/channel/' "$OUT")"

# ---------------------------------------------------------------------------
describe "AC-4: a directory that is not a git repository fails closed"

NOREPO="$WORK/not-a-repo"
mkdir -p "$NOREPO/src/shared"
printf 'return {}\n' > "$NOREPO/src/shared/Stray.luau"

# Fixture control: the temp directory is not inside some enclosing repository
# (if it were, git would silently answer for THAT repository).
assert_eq "fixture control: the directory is not inside any repository" "128" \
  "$(git -C "$NOREPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; printf '%d' $?)"
assert_eq "fixture control: the old pipeline reports nothing here (the second defect)" "" "$(old_pipeline "$NOREPO")"

run_helper "$NOREPO"
assert_eq "exits 2, never 0" "2" "$RC"
assert_eq "stdout is empty - a failure is not an empty stray list" "" "$OUT"
assert_contains "stderr names the directory" "stray-luau: cannot read git status in $NOREPO" "$ERR"

# ---------------------------------------------------------------------------
describe "AC-4: a root that does not exist fails closed too"

MISSING="$WORK/does-not-exist"
run_helper "$MISSING"
assert_eq "exits 2" "2" "$RC"
assert_eq "stdout is empty" "" "$OUT"
assert_contains "stderr names the directory" "stray-luau: cannot read git status in $MISSING" "$ERR"

# ---------------------------------------------------------------------------
describe "AC-5: the three call sites use the helper, fail-closed, and the old pipeline is gone from .claude/tests"

# The three preconditions call the helper with the repo root and merge stderr
# (so a missing helper is a VISIBLE red, not an empty string), and each asserts
# the exit status before asserting the output. Counted as whole lines against
# the exact text the Contract prescribes.
CALL='stray="$(bash "$REPO_ROOT/scripts/stray-luau.sh" "$REPO_ROOT" 2>&1)"; stray_rc=$?'
RC_ASSERT='assert_eq "the stray-luau check ran (exit 0)" "0" "$stray_rc"'

for site in "project-counters.test.sh:1" "harness-gate.test.sh:2"; do
  f="${site%%:*}"; n="${site##*:}"
  assert_eq "$f calls the helper the fail-closed way, $n time(s)" "$n" "$(grep -cxF -- "$CALL" "$TESTS_DIR/$f")"
  assert_eq "$f asserts the helper's exit status, $n time(s)" "$n" "$(grep -cxF -- "$RC_ASSERT" "$TESTS_DIR/$f")"
done

# The existing messages survive verbatim, so a failure still reads as before.
assert_eq "project-counters keeps its precondition message" "1" \
  "$(grep -cF -- 'assert_eq "the working tree carries no stray .luau files, so the baselines mean what they say" "" "$stray"' "$TESTS_DIR/project-counters.test.sh")"
assert_eq "harness-gate keeps its precondition message" "1" \
  "$(grep -cF -- "assert_eq \"the working tree carries no stray .luau files, so 'a clean tree' below is one\" \"\" \"\$stray\"" "$TESTS_DIR/harness-gate.test.sh")"
assert_eq "harness-gate keeps its postcondition message" "1" \
  "$(grep -cF -- 'assert_eq "the probe is gone and the tree is clean again" "" "$stray"' "$TESTS_DIR/harness-gate.test.sh")"

# No `git status --porcelain -- src tests lune` pipeline anywhere under
# .claude/tests/ except this file's own fixture helper. The needle is the
# pipeline's distinctive pathspec; a match anywhere in another suite is a
# call site that was missed, whichever way it is wrapped.
PIPELINE='git status --porcelain -- src tests lune'
leftovers="$(grep -lF -- "$PIPELINE" "$TESTS_DIR"/*.sh | grep -vxF -- "$TESTS_DIR/stray-luau.test.sh")"
assert_eq "no other suite under .claude/tests still runs the old pipeline" "" "$leftovers"
# ...and the needle itself can match: it finds this file's fixture helper.
assert_eq "the leftover needle is live (it matches this suite's own fixture code)" "1" \
  "$(grep -lF -- "$PIPELINE" "$TESTS_DIR"/*.sh | grep -cxF -- "$TESTS_DIR/stray-luau.test.sh")"

summary "stray-luau"
