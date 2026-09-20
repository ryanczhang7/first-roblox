#!/usr/bin/env bash
# THIS PROJECT's gates against the artifacts git does not carry.
#
# THE DEFECT. `scripts/doctor.sh` printed "Everything this project needs is
# installed" and exited 0 in a fresh git worktree where the REQUIRED `typecheck`
# gate could not run one command. That gate opens with
# `test -s globalTypes.d.luau`; the file is the Roblox API type dump, generated
# rather than authored, covered by `.gitignore:76`, and produced only by
# `bash scripts/task.sh install`. git therefore never brings it to a new clone
# or a new worktree. `bash scripts/selftest.sh` there exited 1 with 2 of 18
# suites failing - `harness-gate`, and `project-counters`, which IS the
# `harness` required gate - reporting typecheck faults that read like code
# faults. The same selftest passed 18 of 18 on CI, which runs `task.sh install`
# first. doctor answered "is the toolchain installed?" with yes about a tree
# where a required gate was unrunnable: project.conf's own "a tool with nothing
# to do does not complain", one level up.
#
# WHY A SEPARATE SUITE, and why this one rather than doctor.test.sh:
#   * .claude/tests/doctor.test.sh tests the MACHINERY - derivation, the
#     precondition rule, non-emptiness - against throwaway fixtures, and
#     scripts/refresh-harness.sh REPLACES it wholesale from upstream. Cases
#     added there are lost at the next harness refresh.
#   * this suite tests THIS PROJECT's .claude/harness/project.conf, which is
#     project-owned and which a refresh leaves alone. refresh-harness.sh KEEPS a
#     suite upstream does not ship ("KEPT ... upstream does not ship it -
#     yours"), so it survives - the same reasoning as project-counters.test.sh.
#   * scripts/selftest.sh globs .claude/tests/*.test.sh, so both are discovered.
#
# WHAT IT DOES NOT DO. It never hides the real globalTypes.d.luau to see what
# happens: a suite that moves a file the rest of the run depends on is one
# interrupt away from leaving the tree unrunnable. The real project.conf's own
# `gate` and `artifact` lines are copied into a throwaway repository that does
# not have the file, which is the same condition and is disposable.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

CONF="$REPO_ROOT/.claude/harness/project.conf"
ARTIFACT="globalTypes.d.luau"

FIX="$(make_project_fixture)"
trap 'rm -rf "$FIX"' EXIT

run_doctor() { out="$( cd "$FIX" && bash scripts/doctor.sh 2>&1 )"; rc=$?; }

# real_lines <kind>   Every line of the REAL project.conf whose first field is
# <kind>, parsed the way gates.sh and doctor.sh parse it (`cut -d'|' -f1`,
# trimmed). Copying the lines rather than retyping them is the point: a fixture
# holding its own version of the gate command would assert nothing about the
# file the gates actually read.
real_lines() {
  awk -v want="$1" -F'|' '
    { line = $0; sub(/\r$/, "", line) }
    line ~ /^[[:space:]]*#/ { next }
    line !~ /\|/ { next }
    { k = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", k) }
    k == want { print line }
  ' "$CONF"
}

# ---------------------------------------------------------------------------
describe "the artifact is real: git does not carry it"

# Without this, every assertion below is about a file that a clone would have
# had anyway, and the section is decoration.
if [ -n "$(git -C "$REPO_ROOT" ls-files -- "$ARTIFACT" 2>/dev/null | head -1)" ]; then
  _bad "$ARTIFACT is not tracked by git" "git ls-files reports it as tracked"
else
  _ok "$ARTIFACT is not tracked by git"
fi

if git -C "$REPO_ROOT" check-ignore -q "$ARTIFACT" 2>/dev/null; then
  _ok "and .gitignore covers it, so it is generated rather than forgotten"
else
  _bad "and .gitignore covers it, so it is generated rather than forgotten" \
    "git check-ignore does not match it"
fi

# ---------------------------------------------------------------------------
describe "a required gate cannot run without it"

# Asked of the gate COMMAND in project.conf, not of a copy here. A `typecheck`
# gate rewritten to stop needing the dump should make this go red and be
# re-measured, not silently keep passing.
tc="$(real_lines gate | grep -E '^[[:space:]]*gate[[:space:]]*\|[[:space:]]*typecheck[[:space:]]*\|')"
assert_contains "the typecheck gate is required" "| required |" "$tc"
assert_contains "and names the dump it cannot analyse without" "$ARTIFACT" "$tc"

# ---------------------------------------------------------------------------
describe "doctor reports it missing on a tree that does not have it"

# The real gate and artifact lines, in a repository that has never run
# task.sh install. This IS the fresh-worktree condition.
{ printf 'BOOTSTRAPPED=yes\n'; real_lines gate; real_lines artifact; } \
  > "$FIX/.claude/harness/project.conf"
rm -f "$FIX/$ARTIFACT"
run_doctor
assert_contains "doctor names the missing artifact" "MISSING" "$out"
assert_contains "and it is the type dump" "$ARTIFACT" "$out"
assert_contains "and hands over the command that produces it" \
  "bash scripts/task.sh install" "$out"
# THE HALF A CALLER CAN ACT ON, and the half that was wrong: doctor exited 0.
# Every assertion above this line passes in a doctor that prints its complaint
# and then reports success, which is precisely the defect.
assert_eq "and exits non-zero" 1 "$rc"
case "$out" in
  *"Everything this project needs is installed"*)
    _bad "and does not claim everything is installed" "claimed it anyway" ;;
  *) _ok "and does not claim everything is installed" ;;
esac

# The control. Without it, a doctor that fails on every tree passes all four.
printf 'declare function typeof(v: any): string\n' > "$FIX/$ARTIFACT"
run_doctor
assert_contains "with the dump present it reports ok" "$ARTIFACT present (" "$out"
assert_eq "and exits 0" 0 "$rc"

# Non-emptiness, not existence: a curl interrupted part way leaves a file that
# `test -e` accepts and luau-lsp rejects.
: > "$FIX/$ARTIFACT"
run_doctor
assert_contains "a zero-byte dump is missing, not present" "the file is empty" "$out"
assert_eq "and exits non-zero" 1 "$rc"
rm -f "$FIX/$ARTIFACT"

# ---------------------------------------------------------------------------
describe "the declaration is belt and braces, not the only defence"

# project.conf's `artifact | globalTypes | ...` line supplies the exact remedy,
# which derivation cannot know. But if the whole gap rested on someone
# remembering to write that line, it would reopen the first time a gate grew a
# new precondition. doctor also DERIVES the requirement from the gate command
# itself, and this is the assertion that says so: same tree, same gates, no
# declaration at all.
{ printf 'BOOTSTRAPPED=yes\n'; real_lines gate; } \
  > "$FIX/.claude/harness/project.conf"
run_doctor
assert_contains "with the declaration deleted it is still reported" \
  "$ARTIFACT" "$out"
assert_contains "and still as missing" "MISSING" "$out"
assert_eq "and doctor still exits non-zero" 1 "$rc"

# And the same control, for the same reason.
printf 'declare function typeof(v: any): string\n' > "$FIX/$ARTIFACT"
run_doctor
assert_eq "derivation alone does not fail a tree that has it" 0 "$rc"
rm -f "$FIX/$ARTIFACT"

# ---------------------------------------------------------------------------
describe "the remedy names a task this project actually defines"

# A remedy is an instruction a person or an agent will run. One pointing at a
# task nobody defined is worse than none: it reads as a fix and is a dead end.
decl="$(real_lines artifact | grep -F "$ARTIFACT")"
assert_contains "the dump is declared" "$ARTIFACT" "$decl"

remedy="$(printf '%s' "$decl" | cut -d'|' -f4- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
task_id="$(printf '%s' "$remedy" | awk '{ for (i = 1; i < NF; i++) if ($i ~ /task\.sh$/) { print $(i + 1); exit } }')"
if [ -n "$task_id" ] && [ -n "$(real_lines task | grep -E "^[[:space:]]*task[[:space:]]*\|[[:space:]]*$task_id[[:space:]]*\|")" ]; then
  _ok "and its remedy names a task project.conf defines: $task_id"
else
  _bad "and its remedy names a task project.conf defines" \
    "remedy '$remedy' resolved to task id '$task_id', which project.conf has no 'task |' line for"
fi

# That task is what actually produces the file - not merely a task that exists.
assert_contains "and that task is the one that fetches the dump" "$ARTIFACT" \
  "$(real_lines task | grep -E "^[[:space:]]*task[[:space:]]*\|[[:space:]]*${task_id:-__none__}[[:space:]]*\|")"

summary "project-artifacts"
