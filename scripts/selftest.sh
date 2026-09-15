#!/usr/bin/env bash
# Run the harness's own tests.
#
#   bash scripts/selftest.sh            every suite in .claude/tests
#   bash scripts/selftest.sh phase-guard one suite, by name
#   VERBOSE=1 bash scripts/selftest.sh  name every assertion, not just failures
#
# These test the harness, not the project built with it: the phase lock, the
# path classifier, the hooks. They need bash, git and coreutils and nothing
# else, so they run before a stack has been chosen - which is the point, since
# the harness has to be trustworthy from the first story onwards.
#
# The project's own gates are a separate thing entirely: scripts/gates.sh.
#
# --- On speed, and on what a slow run is not -----------------------------------
#
# These suites spawn thousands of short-lived `git` and `bash` processes. That
# is cheap on Linux and expensive on Windows, where process creation costs
# roughly an order of magnitude more. Measured on Windows 11 under Git Bash:
#
#     phase-guard   200-430s   145 assertions
#     boundaries    110-150s
#     gates         110-150s
#     everything else  1-20s each
#     full sequential run   10-15 minutes
#
# Those are ranges because two clean runs on the same machine differed by
# roughly 2x - process-creation cost here depends on what else is running, and
# on whatever Defender is doing. Do not treat any single figure as the number.
#
# **A quiet ten to fifteen minutes is the expected behaviour on Windows, not a
# hang.**
# Progress is written to stderr, one line per suite as it starts and finishes,
# so that a redirected or backgrounded run shows life immediately rather than
# buffering every byte until exit. That buffering is what made an earlier run
# look dead; the suites were passing the whole time.
#

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ONLY="${1:-}"

suites=()
for suite in "$ROOT"/.claude/tests/*.test.sh; do
  [ -e "$suite" ] || continue
  name="$(basename "$suite" .test.sh)"
  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue
  suites+=("$suite")
done

total=${#suites[@]}
if [ "$total" -eq 0 ]; then
  printf 'No suites matched%s. Looked in .claude/tests/*.test.sh\n' "${ONLY:+ '$ONLY'}" >&2
  exit 1
fi

started=$(date +%s)

# Progress goes to stderr, deliberately: it is the channel that is not captured
# when someone pipes stdout into a file or a pager, so a long run still shows
# that it is moving.
note() { printf '%s\n' "$*" >&2; }

run_one() { # <suite> <index> -> report on stdout, progress on stderr, suite's rc
  local suite="$1" idx="$2" name start end rc out
  name="$(basename "$suite" .test.sh)"
  note "[$idx/$total] $name ..."
  start=$(date +%s)
  out="$(bash "$suite" 2>&1)"; rc=$?
  end=$(date +%s)
  printf '\n=== %s (%ds) ===\n%s\n' "$name" "$((end - start))" "$out"
  if [ "$rc" -eq 0 ]; then
    note "[$idx/$total] $name ok ($((end - start))s)"
  else
    note "[$idx/$total] $name FAILED rc=$rc ($((end - start))s)"
  fi
  return "$rc"
}

fails=0
ran=0

idx=0
for suite in "${suites[@]}"; do
  idx=$((idx + 1))
  run_one "$suite" "$idx" || fails=$((fails + 1))
  ran=$((ran + 1))
done

elapsed=$(( $(date +%s) - started ))

printf '\n'
if [ "$fails" -gt 0 ]; then
  printf '%d of %d harness suite(s) FAILED in %ds.\n' "$fails" "$ran" "$elapsed"
  exit 1
fi
printf '%d harness suite(s) passed in %ds.\n' "$ran" "$elapsed"
