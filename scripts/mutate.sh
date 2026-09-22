#!/usr/bin/env bash
# Apply a diagnostic mutation to one file, run a command against it, and put the
# file back — verifiably.
#
#   bash scripts/mutate.sh <FILE> '<SED-EXPRESSION>' -- <COMMAND> [ARGS...]
#
#   bash scripts/mutate.sh src/camera.ts 's/Math.min(90/Math.min(900/' \
#     -- pnpm exec vitest run tests/camera.test.ts
#
# This is the ONLY sanctioned way to mutate production source, and it is allowed
# in every phase. The phase lock knows about it and does not treat the file it
# names as a write, because the file is restored before this script returns.
#
# Why it exists. The harness requires mutations it did not provide a way to
# make. A test written or corrected while the implementation already exists
# passes on its first execution and every one after, whether or not it asserts
# anything; rules.md says the only thing that earns it is breaking the specific
# production behaviour it claims to pin and watching that one assertion go red.
# In RED, where a corrected test is written, production source is frozen. So the
# same document said "mutate the frozen file" and "never route around the lock",
# and every agent reconciled that privately with `sed -i` — which the lock let
# through only because it discarded any target containing a `$`. Three source
# files were mutated that way in one corrective RED pass. Separately, the one
# mutation made in a phase where source WAS writable lost its backup, because
# the shell had no $TMPDIR, and the restore came down to the substitution
# happening to be an exact inverse of a single-occurrence match.
#
# Hence the two properties that matter more than convenience:
#
#   * The backup is at an explicit path under .claude/state/mutations/, never
#     $TMPDIR, which is not set in every shell this harness runs in.
#   * The restore is CHECKED with cmp and said out loud. A restore that cannot
#     be verified exits 90 and shouts, because the alternative is a mutation
#     left in the tree with a green suite ahead of it.
#
# A mutation that changes nothing is refused before the command runs (exit 3):
# an expression that matches nothing leaves the command green and hands the
# agent a passing test it believes it has earned, which is worse than no probe.
#
# Exit status is the COMMAND's, because a non-zero exit is usually the point —
# the red is the evidence. The exceptions all come with a message: 2 for usage,
# 3 for a mutation that changed nothing (neither reaches the command), and 90
# for a restore that could not be verified, which overrides everything.
#
# Capturing that status through a pipe takes care, and getting it wrong is how
# an agent is handed a clean 0 for a probe that never ran. This script's own
# narration goes to stderr and the command's output to stdout, so the useful
# capture is the MERGED stream — and `mutate ... 2>&1 | head -30` reports
# `head`'s status, not this script's. Read `${PIPESTATUS[0]}` in the same shell
# as the pipeline, or set `pipefail`; the pipeline's plain `$?` is the reader's.
#
# What runs is executed directly, not through a shell, so a redirect or a pipe
# in the payload needs its own `sh -c`. The command runs from the repository
# root, whatever directory you invoked this from.
#
# Deliberately NOT in the allow list in .claude/settings.json, unlike gates.sh and
# phase.sh: everything after `--` is an arbitrary command, so allowlisting this
# script would allowlist every command through it. It is meant to be approved
# per call, like any other command that runs a test suite.
#
# It refuses to mutate ITSELF, for a reason worth knowing before you mutate
# anything a running process reads lazily: see the check below.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MUTDIR="$ROOT/.claude/state/mutations"
LOG="$MUTDIR/log"

usage() {
  printf 'usage: bash scripts/mutate.sh <FILE> '"'"'<SED-EXPRESSION>'"'"' -- <command> [args...]\n' >&2
  printf '\n  e.g. bash scripts/mutate.sh src/camera.ts '"'"'s/90/900/'"'"' -- pnpm exec vitest run\n' >&2
}
die() { printf 'mutate: %s\n' "$1" >&2; usage; exit 2; }

REL="${1:-}"; EXPR="${2:-}"
[ -n "$REL" ] || die "no file given"
[ $# -ge 2 ] || die "no sed expression given"
shift 2
[ -n "$EXPR" ] || die "the sed expression is empty; there is nothing to mutate"
[ "${1:-}" = "--" ] || die "the command must be separated from the expression by -- <command>"
shift
[ $# -ge 1 ] || die "nothing after --; -- <command> is what watches the mutation"
CMD=("$@")

# Resolved against the repository root so that the same invocation works from
# anywhere, which is also what makes the log lines comparable.
case "$REL" in
  /*|?:[/\\]*) FILE="$REL" ;;
  *)           FILE="$ROOT/$REL" ;;
esac
[ -f "$FILE" ] || die "no such file: $REL"

# bash reads a script incrementally rather than loading it whole, so rewriting
# THIS file while it is executing changes what the interpreter reads next: the
# run dies somewhere in the middle and the restore - the last thing it does -
# never happens. The mutation is then left in the tree with nothing to say so,
# which is precisely the outcome this script exists to make impossible. Found by
# probing this script with itself, which is also the only way to find it.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
if [ "$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)/$(basename "$FILE")" = "$SELF" ]; then
  die "cannot mutate itself: bash reads this script as it runs, so the restore would never happen. Copy it elsewhere and mutate the copy."
fi

mkdir -p "$MUTDIR" || die "cannot create $MUTDIR"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SAFE="$(printf '%s' "$REL" | tr '/\\ ' '___')"
BAK="$MUTDIR/$SAFE.$STAMP.$$.bak"
NEW="$MUTDIR/$SAFE.$STAMP.$$.new"

cp "$FILE" "$BAK" || die "cannot back up $REL to $BAK"

# Read from the backup rather than the live file: a `sed` that reads and writes
# the same path truncates it, and this script's whole claim is that it does not
# lose the original.
if ! sed -e "$EXPR" "$BAK" > "$NEW" 2>"$NEW.err"; then
  printf 'mutate: sed rejected the expression:\n' >&2
  sed -e 's/^/  /' "$NEW.err" >&2
  rm -f "$NEW" "$NEW.err" "$BAK"
  exit 2
fi
rm -f "$NEW.err"

# A mutation that mutates nothing. Refused here, before the command runs, so
# that nobody reads the resulting green as a probe that passed.
if cmp -s "$BAK" "$NEW"; then
  printf 'mutate: the expression changed nothing in %s.\n' "$REL" >&2
  printf '  A probe that does not alter behaviour cannot show a test discriminates:\n' >&2
  printf '  the command would have passed for the same reason it passes now. Check the\n' >&2
  printf '  expression against the file and try again.\n' >&2
  printf '%s\t%s\t%s\tCHANGED NOTHING - command not run\n' "$STAMP" "$REL" "$EXPR" >> "$LOG" 2>/dev/null || true
  rm -f "$NEW" "$BAK"
  exit 3
fi

# Which lines moved, and how many. One line is the useful case - a probe aimed
# at a single behaviour, whose predicted catch is a single assertion - so the
# count is printed rather than left to be counted by eye.
CHANGED="$(awk 'NR == FNR { a[FNR] = $0; next } { if ($0 != a[FNR]) c++ } END { print c + 0 }' "$BAK" "$NEW")"
LINES="$(awk 'NR == FNR { a[FNR] = $0; next } $0 != a[FNR] { print FNR }' "$BAK" "$NEW")"

# --- the single exit path ----------------------------------------------------
#
# Everything below leaves through finish(), the ordinary return included, and
# the trap is installed BEFORE the first byte is written to either stream. Both
# halves of that sentence are load-bearing.
#
# WHY IT IS INSTALLED HERE, and not after the banner where it used to be.
# `bash scripts/mutate.sh ... 2>&1 | head -N` is the shape an agent actually
# writes, and a reader that stops reading closes the pipe: the next write kills
# this shell with SIGPIPE. With the trap installed after the banner, a `head -1`
# killed the shell AT the banner - before the trap existed and before the file
# was even mutated - and left the .bak/.new pair behind with no line in the log.
# rules.md and .claude/state/README.md both read a leftover .bak as "a restore
# FAILED and mutate.sh exited 90 saying so", so that was a false alarm in the
# one signal this harness has for a mutation still sitting in the tree.
#
# WHY THE PRINTING IS LAST, and nothing above it writes to either stream. The
# trap is killable in exactly the way the straight-line code was: measured on
# this machine, bash runs the EXIT trap when it dies of SIGPIPE, and the trap
# then dies at its OWN first write. So the file work - restore, cmp, log, clean
# up - is all done before a byte is printed. A trap that printed first would
# reproduce this bug inside its own fix, and `2>&1` puts both streams down the
# same closed pipe, so moving a write to stderr does not by itself make it safe.
MUTATED=0     # has $FILE been overwritten with the mutated copy?
COMPLETED=0   # did the command run to completion - i.e. is this the normal path?
FINISHED=0    # has finish() already run? the log is appended exactly once
rc=0

finish() {
  local st=$?
  trap - EXIT INT TERM
  [ "$FINISHED" = 1 ] && return 0
  FINISHED=1

  # --- file work first: restore, check, log, clean up ---
  local restore verdict='' rcfield='-' outcome
  if [ "$MUTATED" = 1 ]; then
    # COPY, never move. A restore whose target is no longer a regular file -
    # the case the "cannot be verified" test provokes by replacing it with a
    # directory - must leave the backup on disk to be kept.
    cp "$BAK" "$FILE" 2>/dev/null
    if cmp -s "$BAK" "$FILE" 2>/dev/null; then
      restore="restored (verified)"
      verdict="restored (verified byte-for-byte against $BAK)"
    else
      restore="COULD NOT RESTORE"
    fi
  else
    # Died before the mutated copy was ever put in place: nothing was changed,
    # so there is nothing to restore and nothing to keep.
    restore="not mutated"
  fi

  if [ "$COMPLETED" = 1 ]; then
    outcome="$restore"
    rcfield="$rc"
  else
    outcome="INTERRUPTED"$'\t'"$restore"
  fi

  # Appended here and nowhere else, so that a run produces exactly one line
  # whichever way it ended. mkdir because the log must survive a caller that
  # cleared the directory under us.
  mkdir -p "$MUTDIR" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s line(s)\tcommand: %s\texited %s\t%s\n' \
    "$STAMP" "$REL" "$EXPR" "$CHANGED" "${CMD[*]}" "$rcfield" "$outcome" \
    >> "$LOG" 2>/dev/null || true

  # CONDITIONAL, and deliberately so. A leftover .bak is the only signal the
  # harness has that a mutation may still be in the tree; an unconditional
  # `rm -f "$NEW" "$BAK"` here would satisfy every piped case in
  # mutate.test.sh and destroy that signal. The unverified path keeps the
  # backup and removes only the working copy.
  if [ "$restore" = "COULD NOT RESTORE" ]; then
    rm -f "$NEW" 2>/dev/null
  else
    rm -f "$NEW" "$BAK" 2>/dev/null
  fi

  # --- and only now, the printing. All of it on stderr, so that stdout carries
  # the mutated command's own output and nothing else: a caller reading stdout
  # can then stop reading without killing this run at all. ---
  if [ "$restore" = "COULD NOT RESTORE" ]; then
    # The one failure mode that must never be quiet.
    printf '\n=== mutate: COULD NOT RESTORE %s ===\n' "$REL" >&2
    if [ "$COMPLETED" = 1 ]; then
      printf 'The command exited %d, but %s does not match the backup afterwards.\n' "$rc" "$REL" >&2
    else
      printf 'This run ended before the command did, and %s does not match the backup afterwards.\n' "$REL" >&2
    fi
    if [ -f "$BAK" ]; then
      printf 'The original is still at:\n  %s\nPut it back by hand and check nothing else moved.\n' "$BAK" >&2
    else
      printf 'The backup at %s is gone too, so this script cannot help you: check\n' "$BAK" >&2
      printf 'git status and git diff before running anything that judges this tree.\n' >&2
    fi
    exit 90
  fi

  if [ "$COMPLETED" = 1 ]; then
    printf '\n=== mutate: command exited %d; %s ===\n' "$rc" "$verdict" >&2
  elif [ "$MUTATED" = 1 ]; then
    printf '\n=== mutate: ended before the command did; %s ===\n' "$verdict" >&2
  else
    printf '\n=== mutate: ended before %s was mutated; nothing to restore ===\n' "$REL" >&2
  fi
  if [ "$MUTATED" = 1 ]; then
    printf '%s\n' "$LINES" | while IFS= read -r n; do
      [ -n "$n" ] || continue
      printf '  %s: %s\n' "$n" "$(awk -v n="$n" 'FNR == n { print; exit }' "$FILE")" >&2
    done
  fi
  exit "$st"
}
trap finish EXIT INT TERM

printf '=== mutate: %s (%s line(s) changed by %s) ===\n' "$REL" "$CHANGED" "$EXPR" >&2
awk 'NR == FNR { a[FNR] = $0; next }
     $0 != a[FNR] { printf "  %d - %s\n  %d + %s\n", FNR, a[FNR], FNR, $0 }' "$BAK" "$NEW" | head -20 >&2

# Set before the copy rather than after it: a cp that fails halfway has still
# changed the file, and the trap must treat it as mutated and put it back.
MUTATED=1
cp "$NEW" "$FILE" || die "cannot write $REL"

printf '\n=== mutate: running %s ===\n' "${CMD[*]}" >&2
( cd "$ROOT" && "${CMD[@]}" )
rc=$?
COMPLETED=1

# The restore, the check, the log line and the clean-up all happen in finish().
exit "$rc"
