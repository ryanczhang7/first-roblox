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

# The counts this story pins, read out of docs/backlog/stories/HARNESS-006.md
# (AC-7, and PO decision 5's re-measured `gates.sh --fast` at the branch point).
# They are SETTLED, not re-derived: re-deriving them with the new counter is the
# thing AC-7 exists to detect.
BASE_FORMAT=38     # stylua  over src tests lune
BASE_LINT=38       # selene  over src tests lune
BASE_TYPECHECK=7   # analyze over src
NARROW_FORMAT=7    # stylua  over src alone        (Contract, measured)
NARROW_LINT=7      # selene  over src alone
NARROW_TYPECHECK=5 # analyze over src/shared alone

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
  if printf '%s\n' "$2" | grep -qE -- "$3"; then
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

stray="$( cd "$REPO_ROOT" && git status --porcelain -- src tests lune | grep -E '\.luau$' || true )"
assert_eq "the working tree carries no stray .luau files, so the baselines mean what they say" "" "$stray"

assert_eq "project.conf declares a format gate command"    "0" "$(gate_cmd format    > /dev/null; printf '%d' $?)"
assert_eq "project.conf declares a lint gate command"      "0" "$(gate_cmd lint      > /dev/null; printf '%d' $?)"
assert_eq "project.conf declares a typecheck gate command" "0" "$(gate_cmd typecheck > /dev/null; printf '%d' $?)"

CMD_FORMAT="$(gate_cmd format)";       EV_FORMAT="$(gate_evidence format)"
CMD_LINT="$(gate_cmd lint)";           EV_LINT="$(gate_evidence lint)"
CMD_TYPECHECK="$(gate_cmd typecheck)"; EV_TYPECHECK="$(gate_evidence typecheck)"

# ---------------------------------------------------------------------------
# AC-7 - the fix corrects WHAT is measured, not the measurement. 38 / 38 / 7,
# read out of the story rather than re-derived. Each also asserts the gate's own
# evidence regex still matches its output, because the count is only "the count
# the gate reports" if gates.sh can find it.
describe "AC-7: the three gates report the same counts as before this story"

run_conf_cmd "$CMD_FORMAT"
assert_zero     "the format gate passes on the unmodified tree"     "$RC" "$OUT"
assert_observed "format reports 38 files on the unmodified tree"    "$BASE_FORMAT" "$OUT" "$EV_FORMAT"

run_conf_cmd "$CMD_LINT"
assert_zero     "the lint gate passes on the unmodified tree"       "$RC" "$OUT"
assert_observed "lint reports 38 files on the unmodified tree"      "$BASE_LINT" "$OUT" "$EV_LINT"

run_conf_cmd "$CMD_TYPECHECK"
assert_zero     "the typecheck gate passes on the unmodified tree"  "$RC" "$OUT"
assert_observed "typecheck reports 7 files on the unmodified tree"  "$BASE_TYPECHECK" "$OUT" "$EV_TYPECHECK"

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

assert_narrowed_count "narrowing the format target to src reports 7, not 38" \
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

assert_narrowed_count "narrowing the lint target to src reports 7, not 38" \
  "$CMD_LINT" "$EV_LINT" 'src tests lune' 'src' "$NARROW_LINT"

# ---------------------------------------------------------------------------
describe "AC-5: the typecheck count moves with the target luau-lsp was handed"

assert_narrowed_count "narrowing the typecheck target to src/shared reports 5, not 7" \
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
assert_observed "AC-2: format counts the untracked file (38 -> 39)" "$((BASE_FORMAT + 1))" "$OUT" "$EV_FORMAT"

run_conf_cmd "$CMD_LINT"
assert_zero     "AC-4: the lint gate still passes with the untracked file present"   "$RC" "$OUT"
assert_observed "AC-4: lint counts the untracked file (38 -> 39)"   "$((BASE_LINT + 1))" "$OUT" "$EV_LINT"

# The Contract applies the same `--cached --others --exclude-standard` rule to
# typecheck; luau-lsp walks src the same way selene walks its target.
run_conf_cmd "$CMD_TYPECHECK"
assert_zero     "the typecheck gate still passes with the untracked file present"    "$RC" "$OUT"
assert_observed "typecheck counts the untracked file (7 -> 8)"      "$((BASE_TYPECHECK + 1))" "$OUT" "$EV_TYPECHECK"

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
assert_observed "format does not count the ignored file (still 38)"    "$BASE_FORMAT" "$OUT" "$EV_FORMAT"

run_conf_cmd "$CMD_LINT"
assert_zero     "the lint gate still passes with an ignored .luau file present"      "$RC" "$OUT"
assert_observed "lint does not count the ignored file (still 38)"      "$BASE_LINT" "$OUT" "$EV_LINT"

run_conf_cmd "$CMD_TYPECHECK"
assert_zero     "the typecheck gate still passes with an ignored .luau file present" "$RC" "$OUT"
assert_observed "typecheck does not count the ignored file (still 7)"  "$BASE_TYPECHECK" "$OUT" "$EV_TYPECHECK"

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
