#!/usr/bin/env bash
# HARNESS-008 - the fast loop sees a harness suite it just broke.
#
# THE DEFECT. `scripts/gates.sh` and `gates.sh --fast` never invoked
# `.claude/tests/*`. The harness suites ran only from `scripts/selftest.sh` and
# `scripts/ci-local.sh`, neither of which is part of RED or GREEN. So a product
# story that changed the project tree could break a harness suite while every
# local gate stayed green - SEAT-001 added one `.luau` under src/ and reached CI
# with `project-counters: 29 passed, 11 failed`.
#
# THE FIX THIS SUITE PINS: a `gate | harness | required | ...` line in
# `.claude/harness/project.conf`, NOT marked `slow`, whose command runs the one
# harness suite AC-1 found reads the real tree - project-counters - and whose
# `evidence` line proves the suite actually ran.
#
# WHY IT LIVES HERE. Like project-counters.test.sh it tests THIS PROJECT's
# project.conf against the real tree, so it reads the real checkout on purpose
# (the _lib.sh header's "never against this checkout" is the rule for suites
# that test the harness machinery; this one tests the project's manifest).
# refresh-harness.sh KEEPS suites upstream does not ship, so it survives a
# refresh, which scripts/gates.sh does not.
#
# WHAT IT COSTS. Two runs of the counters suite (~20 s each on this machine,
# quiet; 13 s on CI) and ONE `gates.sh --fast --gate harness` invocation, whose
# startup alone is ~2.5 min here (gates.sh forks per line of a 521-line
# project.conf - HARNESS-008 PO decision 3; seconds on CI). `--gate harness`
# rather than a bare `--fast` because `--gate` filters BEFORE the `slow` skip
# (gates.sh: the $ONLY check precedes the --fast/slow check), so
# `--fast --gate harness` runs the gate iff it is in the fast subset - verified
# by execution in a fixture during RED. Never a bare `bash scripts/gates.sh`:
# a full run rewrites the ACTIVE story's `## Gate results`, which is stamped
# evidence check-boundaries.sh verifies against the tree.
#
# THIS SUITE MUST NOT BE PART OF THE GATE IT TESTS. It would recurse: the gate
# runs the suite, the suite runs the gate. The guard below makes that a fast,
# named failure rather than a hang - and it is why AC-1's qualifying set
# excludes this file even though, by the operational rule, an extra .luau under
# src/ breaks it too.
#
# REQUIRES THE TOOLCHAIN, for the same reason project-counters does: the gate
# command runs that suite. A missing tool is a hard failure, never a skip.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# --- recursion guard ----------------------------------------------------------
# Set for every child this suite starts. If the harness gate's command reaches
# this file - directly, through a glob over .claude/tests, or through
# scripts/selftest.sh - the nested copy exits here, the gate fails, and the
# outer "passes on a clean tree" assertion shows this message.
if [ -n "${HARNESS_GATE_UNDER_TEST:-}" ]; then
  printf 'FAIL harness-gate: the harness gate invoked the suite that tests it (recursion).\n'
  printf '     The gate runs the suites AC-1 identified - project-counters - never\n'
  printf '     harness-gate.test.sh, a glob over .claude/tests, or scripts/selftest.sh.\n'
  exit 1
fi
export HARNESS_GATE_UNDER_TEST=1

CONF="$REPO_ROOT/.claude/harness/project.conf"
GATE_ID="harness"
COUNTERS_REL=".claude/tests/project-counters.test.sh"
THIS_SUITE="harness-gate.test.sh"

# The probe that reproduces SEAT-001: one well-formed, untracked .luau under
# src/. Named `__probe_*` so paths.conf classifies it as `test` (rules.md), and
# named for THIS story so it cannot collide with the probes project-counters
# writes and removes on its own EXIT trap while it runs.
PROBE_REL="src/shared/__probe_h008_added.luau"
PROBE="$REPO_ROOT/$PROBE_REL"

cleanup() { rm -f "$PROBE"; return 0; }
trap cleanup EXIT

# --- reading project.conf the way gates.sh reads it ---------------------------
# Pure bash, copied from project-counters.test.sh for the same reason it is pure
# bash there: a fork per line over a 500-line conf is minutes on Windows.
_trim_var() { # <text> -> TRIMMED
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  TRIMMED="$s"
}

# Two readers, because gates.sh reads a `gate` line with TWO cut shapes and the
# difference is the whole of HARNESS-008's Return 1:
#
#   req=$(cut -d'|' -f3)   cwd=$(cut -d'|' -f4)     one field, stops at the next |
#   cmd=$(cut -d'|' -f5-)  evidence: cut -f3-       the remainder, | and all
#
# conf_value is `-fN-` (the remainder): right for `gate` f5 and `evidence` f3,
# where a regex may itself contain `|`. conf_field is `-fN` (one field): the
# only correct reader for `gate` f3 and f4. Asking conf_value for f3 returned
# `required | . | bash ...`, which no gate line can make equal `required` and
# still carry a command - and made the cwd `. | bash ...`, so run_gate_cmd's
# `cd` failed and the gate command never ran (Return 1, defect 1).
_conf_rest() { # <kind> <id> <from> -> REST = raw text from field `from` onward; 1 if no line
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
    REST="$rest"
    return 0
  done < "$CONF"
  return 1
}

conf_value() { # <kind> <id> <from> -> fields `from`.. as one value (cut -fN-); 1 if no line
  _conf_rest "$1" "$2" "$3" || return 1
  _trim_var "$REST"
  printf '%s' "$TRIMMED"
}

conf_field() { # <kind> <id> <n> -> field n alone (cut -fN); 1 if no line
  _conf_rest "$1" "$2" "$3" || return 1
  _trim_var "${REST%%|*}"
  printf '%s' "$TRIMMED"
}

# run_gate_cmd   Runs the gate command the way gates.sh runs it: from
# $ROOT/$cwd, in a subshell that inherits `set -o pipefail`. Sets OUT and RC.
#
# RC has two values that mean "the command never ran", and any assertion that
# reads RC as "the gate detected something" has to refuse both (Return 1,
# defect 2 - the old `[ $RC -ne 0 ]` accepted 97 and reported the gate catching
# the SEAT-001 tree while its `cd` had failed and nothing was executed):
#   NEVER_RAN_CD   97   this function's own sentinel: `cd $ROOT/$cwd` failed
#   126 / 127           the shell's: found but not executable / not found -
#                       `bash nope.test.sh` is 127 too, from bash itself.
# project-counters exits 0 or 1 (summary), so neither collides with a real run.
NEVER_RAN_CD=97
run_gate_cmd() {
  OUT="$( cd "$REPO_ROOT/$GATE_CWD" || exit "$NEVER_RAN_CD"
          set -o pipefail
          eval "$GATE_CMD" 2>&1 )"
  RC=$?
}

# work_count <output> <evidence regex>   The number gates.sh reports as
# "observed": the first run of digits at or after the start of the first
# evidence match (project.conf's header rule, and gates.sh's work_count).
work_count() {
  printf '%s\n' "$1" | sed -e 's/\r$//' \
    | grep -oE -m1 -- "($2).*" 2>/dev/null | head -1 \
    | grep -oE '[0-9]+' 2>/dev/null | head -1
}

# has_line <output> <anchored ERE>   0 if some whole line matches.
has_line() { printf '%s\n' "$1" | sed -e 's/\r$//' | grep -qE -- "$2"; }

_tail() { printf '%s\n' "$1" | tail -8; }

# The line the counters suite prints last. Anchored, so that `0 failed`
# cannot satisfy the "broke" needle and `0 passed` cannot satisfy the "ran" one.
RAN_OK='^project-counters: [1-9][0-9]* passed, 0 failed$'
BROKE='^project-counters: [0-9]+ passed, [1-9][0-9]* failed$'

# =============================================================================
describe "preconditions"

missing=""
for t in stylua selene rojo luau-lsp git; do
  command -v "$t" > /dev/null 2>&1 || missing="$missing $t"
done
assert_eq "the pinned toolchain is on PATH (the gate runs project-counters, which needs it)" "" "$missing"
if [ -n "$missing" ]; then
  printf '\n  Cannot run the harness-gate tests without%s.\n' "$missing"
  printf '  Put ~/.rokit/bin on PATH, or run: bash scripts/task.sh install\n'
  printf '  This suite is NOT skippable, for the same reason project-counters is not.\n'
  summary "harness-gate"
  exit 1
fi

assert_eq "the suite AC-1 identified exists: $COUNTERS_REL" "0" \
  "$(test -f "$REPO_ROOT/$COUNTERS_REL"; printf '%d' $?)"

stray="$( cd "$REPO_ROOT" && git status --porcelain -- src tests lune | grep -E '\.luau$' || true )"
assert_eq "the working tree carries no stray .luau files, so 'a clean tree' below is one" "" "$stray"

# =============================================================================
# AC-1 / AC-2, the manifest half. gates.sh decides what --fast runs from
# these lines and nothing else, so each is asserted as gates.sh would read it.
describe "AC-1: project.conf has a required, not-slow gate that runs the real-tree suite"

if GATE_CMD="$(conf_value gate "$GATE_ID" 5)"; then
  _ok "project.conf declares a 'gate | $GATE_ID' line"
else
  GATE_CMD=""
  _bad "project.conf declares a 'gate | $GATE_ID' line" \
"no 'gate | $GATE_ID | ...' line in .claude/harness/project.conf. This is the
gate HARNESS-008 adds: without it nothing in the RED/GREEN loop runs the
harness suites that read the real tree, and a product story can break
project-counters with every local gate green (SEAT-001, CI run 35179368944)."
fi
GATE_REQ="$(conf_field gate "$GATE_ID" 3)" || GATE_REQ=""
GATE_CWD="$(conf_field gate "$GATE_ID" 4)" || GATE_CWD=""
[ -z "$GATE_CWD" ] && GATE_CWD="."
GATE_EV="$(conf_value evidence "$GATE_ID" 3)" || GATE_EV=""

assert_eq "the $GATE_ID gate is required, so its failure fails the run" "required" "$GATE_REQ"
assert_eq "the $GATE_ID gate has a command" "0" "$(test -n "$GATE_CMD"; printf '%d' $?)"

# `slow` is the tempting way to buy AC-6, and it is exactly the hole this story
# closes: a slow gate is left out of --fast. Meaningful only once the gate
# exists, so the two are one assertion.
if [ -n "$GATE_CMD" ] && ! conf_value slow "$GATE_ID" 3 > /dev/null; then
  _ok "the $GATE_ID gate is in the fast subset: it exists and carries no 'slow' line"
elif [ -n "$GATE_CMD" ]; then
  _bad "the $GATE_ID gate is in the fast subset: it exists and carries no 'slow' line" \
"project.conf marks '$GATE_ID' slow: $(conf_value slow "$GATE_ID" 3)
--fast skips slow gates, so RED and GREEN would not see the suite break."
else
  _bad "the $GATE_ID gate is in the fast subset: it exists and carries no 'slow' line" \
       "there is no $GATE_ID gate to be in any subset"
fi

# The set AC-1 derived: project-counters is the ONE suite a product story can
# break (it reads project.conf, src, tests and lune through git and the real
# toolchain). Every other suite drives a fixture, or reads only harness-owned
# paths a product story never touches - and adding one buys cost with no
# detection (## Out of scope). This suite is excluded because it would recurse.
case "$GATE_CMD" in
  *project-counters*) _ok "the gate command runs project-counters, the suite that reads the real tree" ;;
  *) _bad "the gate command runs project-counters, the suite that reads the real tree" \
          "command: ${GATE_CMD:-<none>}" ;;
esac
excluded=""
for s in boundaries ci-local classify doctor gate-reminder gates lib mutate new-story \
         phase-guard phase plan profiles refresh settings harness-gate; do
  case "$GATE_CMD" in *"$s.test.sh"*|*"selftest.sh $s"*) excluded="$excluded $s" ;; esac
done
# Vacuous on an empty command - an absent gate names nothing - so it needs one.
if [ -n "$GATE_CMD" ]; then
  assert_eq "the gate command names no fixture-only suite (cost without detection) and not this one (recursion)" "" "$excluded"
else
  _bad "the gate command names no fixture-only suite (cost without detection) and not this one (recursion)" \
       "there is no gate command to check"
fi

# scripts/doctor.sh takes the FIRST TOKEN of every gate command as the tool to
# look for on PATH (doctor.sh, `exe=$(printf '%s' "$cmd" | awk '{print $1}')`).
# A command starting `X=...; bash ...` makes doctor report a missing tool
# called `X=...` forever. Same guard project-counters keeps for its gates.
exe="$(printf '%s' "$GATE_CMD" | awk '{print $1}')"
assert_eq "the gate command's first token (${exe:-<none>}) is on PATH, as scripts/doctor.sh requires" "0" \
  "$(test -n "$exe" && command -v "$exe" > /dev/null 2>&1; printf '%d' $?)"

# =============================================================================
# AC-4. Exit 0 is the absence of a complaint, not proof of work. The evidence
# regex is what turns "the gate exited 0" into "the gate ran the suite", and a
# `-` declares liveness unassertable, which for a test suite it is not.
describe "AC-4: on a clean tree the gate passes and its evidence line proves the suite ran"

if [ -n "$GATE_EV" ] && [ "$GATE_EV" != "-" ]; then
  _ok "project.conf declares an evidence regex for the $GATE_ID gate"
else
  _bad "project.conf declares an evidence regex for the $GATE_ID gate" \
"no usable 'evidence | $GATE_ID | <regex>' line (found: '${GATE_EV:-<none>}').
Without one gates.sh reports PASS for a command that ran nothing."
fi

if [ -n "$GATE_CMD" ]; then
  run_gate_cmd
  CLEAN_OUT="$OUT"
  if [ "$RC" -eq 0 ]; then _ok "the gate command exits 0 on the unmodified tree"
  else _bad "the gate command exits 0 on the unmodified tree" "expected exit 0; got $RC
gate output (last 8 lines):
$(_tail "$OUT")"; fi
  if has_line "$OUT" "$RAN_OK"; then _ok "and its output carries project-counters' own summary line, all passed"
  else _bad "and its output carries project-counters' own summary line, all passed" \
    "no line matching /$RAN_OK/
gate output (last 8 lines):
$(_tail "$OUT")"; fi
else
  CLEAN_OUT=""
  _bad "the gate command exits 0 on the unmodified tree" "there is no $GATE_ID gate command to run"
  _bad "and its output carries project-counters' own summary line, all passed" "nothing ran"
fi

# Never grep with an empty pattern: '' matches everything, and an assertion
# that cannot fail is not one.
if [ -n "$GATE_EV" ] && [ "$GATE_EV" != "-" ] && [ -n "$CLEAN_OUT" ]; then
  if printf '%s\n' "$CLEAN_OUT" | sed -e 's/\r$//' | grep -qE -- "$GATE_EV"; then
    _ok "the evidence regex matches the clean run's output"
  else
    _bad "the evidence regex matches the clean run's output" "evidence regex: $GATE_EV
gate output (last 8 lines):
$(_tail "$CLEAN_OUT")"
  fi
  n="$(work_count "$CLEAN_OUT" "$GATE_EV")"
  if [ -n "$n" ] && [ "$n" -ge 1 ]; then
    _ok "and gates.sh would observe a count of at least 1 from it (observed $n)"
  else
    _bad "and gates.sh would observe a count of at least 1 from it" \
"work_count read '${n:-<nothing>}' - the regex must start at or before a
number that counts assertions or suites run, so a 'floor' could be set on it.
evidence regex: $GATE_EV"
  fi
else
  _bad "the evidence regex matches the clean run's output" "no evidence regex, or no clean run to match it against"
  _bad "and gates.sh would observe a count of at least 1 from it" "no evidence regex, or no clean run to measure"
fi

# -----------------------------------------------------------------------------
# The control AC-4 names: a gate that ran nothing must fail its evidence line.
# Three outputs that mean "nothing ran", none of which the regex may match:
#   (a) nothing at all - a command that printed nothing and exited 0;
#   (b) bash failing to find the suite (## Notes mutation 2). gates.sh reports
#       that as FAIL exit 127 before evidence is consulted - measured in RED -
#       so this pins the regex's own answer, not the runner's;
#   (c) a suite that ran zero assertions: `summary` prints exactly this and
#       exits 0. Only an assertion-count regex can refuse it; a suite-count
#       regex refuses it trivially by shape, which is fine - it is the vacuous
#       pass, and either regex has to say no.
describe "AC-4 control: the evidence regex refuses a run that did nothing"

if [ -n "$GATE_EV" ] && [ "$GATE_EV" != "-" ]; then
  for ctl in 'nothing printed at all|' \
             'bash could not find the suite|bash: .claude/tests/nope.test.sh: No such file or directory' \
             'a suite with zero assertions|project-counters: 0 passed, 0 failed'; do
    label="${ctl%%|*}"; text="${ctl#*|}"
    if printf '%s\n' "$text" | grep -qE -- "$GATE_EV"; then
      _bad "does not match: $label" "the evidence regex /$GATE_EV/ matched: '$text'
gates.sh would report PASS with evidence for a gate that ran nothing"
    else
      _ok "does not match: $label"
    fi
  done
else
  for label in 'nothing printed at all' 'bash could not find the suite' 'a suite with zero assertions'; do
    _bad "does not match: $label" "no evidence regex to test"
  done
fi

# =============================================================================
# AC-2, the SEAT-001 incident. One untracked .luau under src/ moves every
# count project-counters pins (43 -> 44, 8 -> 9) and trips its stray-file
# precondition, so the suite goes red - as it did in CI, 29 passed, 11 failed.
# Before this story, nothing in the RED/GREEN loop ran that suite.
describe "AC-2: with one .luau added under src/, the gate command fails and names the suite"

printf -- '--!strict\nlocal M = {}\nreturn M\n' > "$PROBE"
assert_eq "the probe is untracked (precondition: that is what a product story's new file is)" "" \
  "$( cd "$REPO_ROOT" && git ls-files -- "$PROBE_REL" )"
assert_eq "the probe is not ignored (precondition: an ignored file is not counted)" "1" \
  "$( cd "$REPO_ROOT" && git check-ignore -q "$PROBE_REL"; printf '%d' $? )"

# The instrument, checked against its own negation before it is trusted: the
# "broke" needle must not be satisfied by an all-green summary.
if has_line 'project-counters: 40 passed, 0 failed' "$BROKE"; then
  _bad "instrument: the 'suite broke' needle rejects an all-green summary" "/$BROKE/ matched '40 passed, 0 failed'"
else
  _ok "instrument: the 'suite broke' needle rejects an all-green summary"
fi

if [ -n "$GATE_CMD" ]; then
  run_gate_cmd
  # Non-zero AND not a "never ran" code. `-ne 0` alone is a needle that cannot
  # fail: a cd that fails (97) or a command the shell cannot run (126/127)
  # satisfies it without the suite ever seeing the probe (Return 1, defect 2).
  case "$RC" in
    0) _bad "the gate command exits non-zero with the probe present" \
"expected a NON-ZERO exit; got 0 - the gate would PASS on the SEAT-001 tree
gate output (last 8 lines):
$(_tail "$OUT")" ;;
    "$NEVER_RAN_CD") _bad "the gate command exits non-zero with the probe present" \
"got $RC, run_gate_cmd's own sentinel: 'cd $REPO_ROOT/$GATE_CWD' FAILED and the
gate command never ran. A non-zero exit from a command that did not execute is
not the gate detecting the probe. cwd as parsed: [$GATE_CWD]
gate output (last 8 lines):
$(_tail "$OUT")" ;;
    126|127) _bad "the gate command exits non-zero with the probe present" \
"got $RC, the shell's 'cannot execute' / 'not found': the gate command never ran.
A non-zero exit from a command that did not execute is not the gate detecting
the probe. command: [$GATE_CMD]
gate output (last 8 lines):
$(_tail "$OUT")" ;;
    *) _ok "the gate command exits non-zero with the probe present" ;;
  esac
  if has_line "$OUT" "$BROKE"; then _ok "and its output names project-counters as the suite that broke"
  else _bad "and its output names project-counters as the suite that broke" \
    "no line matching /$BROKE/
gate output (last 8 lines):
$(_tail "$OUT")"; fi
else
  _bad "the gate command exits non-zero with the probe present" "there is no $GATE_ID gate command to run"
  _bad "and its output names project-counters as the suite that broke" "nothing ran"
fi

# -----------------------------------------------------------------------------
# End to end, through the runner the loop actually uses. `--fast --gate
# harness` is `--fast`'s verdict on this one gate: --gate filters first, then
# the slow skip, so a slow-marked gate is SKIPPED here and this block goes red
# (## Notes mutation 1). Not a bare run: see the header.
describe "AC-2, end to end: 'gates.sh --fast' fails on that tree and says which gate and suite"

out="$( cd "$REPO_ROOT" && bash scripts/gates.sh --fast --gate "$GATE_ID" 2>&1 )"; rc=$?
if [ "$rc" -eq 1 ]; then _ok "gates.sh --fast --gate $GATE_ID exits 1 (a required gate failed)"
else _bad "gates.sh --fast --gate $GATE_ID exits 1 (a required gate failed)" "expected exit 1; got $rc
output (last 8 lines):
$(_tail "$out")"; fi
assert_contains "the summary reports the $GATE_ID gate as FAIL" "FAIL         $GATE_ID" "$out"
assert_contains "and counts it as a required failure" "1 required gate(s) failed" "$out"
if has_line "$out" "$BROKE"; then _ok "and the streamed output names project-counters as the suite that broke"
else _bad "and the streamed output names project-counters as the suite that broke" \
  "no line matching /$BROKE/
output (last 8 lines):
$(_tail "$out")"; fi
# The absence of a skip line means nothing unless the run reached the point
# that prints one: a run refused at option parsing has no skip line either.
case "$out" in
  *"--fast skipped: $GATE_ID"*|*"--fast skipped:"*" $GATE_ID"*)
    _bad "--fast did not skip the $GATE_ID gate" "it did: the gate is marked slow, and the fast loop cannot see it break
$(printf '%s\n' "$out" | grep -- '--fast skipped')" ;;
  *"--- gate summary ---"*) _ok "--fast did not skip the $GATE_ID gate" ;;
  *) _bad "--fast did not skip the $GATE_ID gate" "the run never reached the gate summary, so nothing was run or skipped
output (last 8 lines):
$(_tail "$out")" ;;
esac

rm -f "$PROBE"
assert_eq "the probe is gone and the tree is clean again" "" \
  "$( cd "$REPO_ROOT" && git status --porcelain -- src tests lune | grep -E '\.luau$' || true )"

summary "harness-gate"
