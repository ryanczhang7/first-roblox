#!/usr/bin/env bash
# Record the blob hash of the files a phase must not touch, and check it later.
#
#   bash scripts/frozen.sh snapshot <path>...   before the phase starts
#   bash scripts/frozen.sh verify               before the phase ends
#
# Why it exists. Stories used to prove a freeze held by showing
# `git diff --stat <file>` empty. That is right at RED, where the frozen file is
# source and its last committed state is the previous merge. It is wrong at
# GREEN and GATES: the frozen file is then a test whose RED work is NOT
# committed (a story commits once, at GATES->REVIEW), so the diff is non-empty on
# every healthy GREEN, and the only way to make it empty is to revert the tests -
# the violation the check was written to catch. `git diff` is also blind to an
# untracked file, which is what a new test file is. The check that works is the
# blob hash, taken before the phase and compared after (HARNESS-015).
#
# The snapshot lives at .claude/state/frozen-<STORY_ID>.tsv, one per story, so a
# record taken for one story never answers for another. One row per argument,
# `<path><TAB><hash>`, with ABSENT for a path that does not exist: freezing a
# file freezes its absence too. It is evidence, so Write/Edit are denied on it
# in settings.json; re-running `snapshot` replaces it, which is the known limit.
#
# This script writes nothing outside .claude/state/. Hashes come from
# `git hash-object` WITHOUT -w, so not even an object is added to .git/.
#
# Exit: 0 snapshot taken / verify OK; 1 CHANGED, NO SNAPSHOT or NO STORY;
# 2 usage error.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT/.claude/state"
ENV_FILE="$STATE_DIR/current-story.env"
D=$'\xe2\x80\x94'   # U+2014

usage() {
  echo "usage: bash scripts/frozen.sh snapshot <path>... | verify" >&2
  exit 2
}

# hash_of <path>   The blob hash, or ABSENT for a path that does not exist.
hash_of() {
  if [ -e "$1" ]; then git hash-object -- "$1"; else echo ABSENT; fi
}

story_id() {
  if [ ! -f "$ENV_FILE" ]; then
    echo "frozen: NO STORY $D no active story (.claude/state/current-story.env is missing); start one with bash scripts/phase.sh set <ID> <PHASE>"
    exit 1
  fi
  ID="$(grep -E '^STORY_ID=' "$ENV_FILE" | head -n 1 | cut -d= -f2- | tr -d '\r')"
  if [ -z "$ID" ]; then
    echo "frozen: NO STORY $D current-story.env has no STORY_ID; start one with bash scripts/phase.sh set <ID> <PHASE>"
    exit 1
  fi
  RECORD="$STATE_DIR/frozen-$ID.tsv"
}

verb="${1:-}"
[ $# -gt 0 ] && shift
case "$verb" in
  snapshot)
    [ $# -gt 0 ] || usage
    story_id
    rows=""
    for p in "$@"; do
      hash="$(hash_of "$p")" || { echo "frozen: cannot hash $p" >&2; exit 1; }
      rows+="$p"$'\t'"$hash"$'\n'
    done
    printf '%s' "$rows" > "$RECORD"
    echo "frozen: snapshot of $# path(s) recorded for $ID in .claude/state/frozen-$ID.tsv"
    ;;
  verify)
    [ $# -eq 0 ] || usage
    story_id
    if [ ! -f "$RECORD" ]; then
      echo "frozen: NO SNAPSHOT $D nothing recorded for $ID; take one before the phase starts"
      exit 1
    fi
    n=0 bad=0
    while IFS=$'\t' read -r p recorded; do
      recorded="${recorded%$'\r'}"
      [ -n "$p" ] || continue
      n=$((n + 1))
      now="$(hash_of "$p")"
      [ "$now" = "$recorded" ] && continue
      bad=$((bad + 1))
      suffix=""
      [ "$recorded" = ABSENT ] && suffix=" (added)"
      [ "$now" = ABSENT ] && suffix=" (deleted)"
      echo "frozen: CHANGED $D $p: recorded $recorded, now $now$suffix"
    done < "$RECORD"
    [ "$bad" -eq 0 ] || exit 1
    echo "frozen: OK $D $n path(s) unchanged since the snapshot for $ID"
    ;;
  *)
    usage
    ;;
esac
