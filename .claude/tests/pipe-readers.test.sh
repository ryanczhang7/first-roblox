#!/usr/bin/env bash
# HARNESS-018 - nothing pipes into a reader that exits at its first match.
#
# THE DEFECT, FIFTH TIME: `producer | grep -q needle`. grep -q exits at the first
# match; if the producer still has more to write than the pipe buffer holds, it
# dies of SIGPIPE, and `set -o pipefail` (which _lib.sh, every script in
# scripts/ and every hook sets) makes 141 the pipeline's status. The needle was
# FOUND and the pipeline says it was not. It is a race on the pipe buffer, so it
# passes on one machine and fails on another, and passes on re-run: CI run
# 36503368294 failed `profile-counters.test.sh: line 319: printf: write error:
# Broken pipe` and went green with no code change.
#
# plan.sh, check-boundaries.sh and doctor.sh each fixed their own instance and
# documented it beside the fix, and the shape kept coming back somewhere else.
# So this suite pins the RULE, not the one line (AC-3), plus the two sites where
# the race can be lost with realistic input (AC-1, AC-2).
#
# WHY A FILE OF OUR OWN: most of the files it polices are upstream's, and
# scripts/refresh-harness.sh replaces them wholesale. Upstream ships no file of
# this name, so a refresh that puts a pipe back fails the `harness` gate here
# instead of quietly reintroducing the flake.
#
# bash, awk and coreutils only.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# 1.5 MiB, the size boundaries.test.sh settled on: the pipe buffer differs
# between machines (64 KiB here, more elsewhere), and a test for a race on it
# has to lose the race on every one of them - not only on the one it was
# written on.
BIG_BYTES=1572864
filler() { yes 'filler line that names nothing in particular' | head -c "$BIG_BYTES"; }

# ---------------------------------------------------------------------------
describe "AC-1: missing_tokens finds a token early in a large text"

# Extracted, not sourced: sourcing the suite would run it.
PC="$REPO_ROOT/.claude/tests/profile-counters.test.sh"
fn="$(awk '/^missing_tokens\(\) *\{/ { on = 1 } on { print } on && /^}/ { exit }' "$PC")"
if [ -z "$fn" ]; then
  _bad "missing_tokens is defined in profile-counters.test.sh" "no '^missing_tokens() {' in $PC"
else
  eval "$fn"
  big="$(printf 'the Verified banner names stylua first\n'; filler)"
  assert_eq "the text really is large" "yes" \
    "$([ "${#big}" -gt "$BIG_BYTES" ] && echo yes || echo "no (${#big} bytes)")"

  # Three calls, all of which must be clean. Once would make "deterministic" a
  # claim about one draw.
  clean=0; seen=""
  for i in 1 2 3; do
    got="$(missing_tokens "$big" stylua 2>/dev/null)"
    if [ -z "$got" ]; then clean=$((clean+1)); else seen="$seen [$got]"; fi
  done
  assert_eq "a token on line 1 of 1.5 MiB is found on 3 of 3 calls" "3${seen}" "$clean${seen}"

  # Control: the fix must not make the check a formality.
  got="$(missing_tokens "$big" stylua zq-nowhere-token 2>/dev/null)"
  assert_eq "a token that appears nowhere is still reported missing" "zq-nowhere-token" "$got"
fi

# ---------------------------------------------------------------------------
describe "AC-2: gates.sh reads a large log's first line"

FIX="$(make_project_fixture)"
trap 'rm -rf "$FIX"' EXIT
# grep -v and tail both read to the end, so neither can cause the defect under
# test; they only keep 2 MB of `seq` out of the assertion messages.
gates() { ( cd "$FIX" && bash scripts/gates.sh "$@" 2>&1 ) | grep -v '^[0-9]*$' | tail -n 20; }

write_conf "$FIX" <<'EOF'
gate     | unit | required | . | { printf 'Tests  47 passed (47)\n'; seq 1 300000; }
evidence | unit | Tests +[1-9][0-9]* passed
EOF
out="$(gates)"
assert_contains "evidence on line 1 of 2 MB is PASS" "PASS         unit" "$out"
case "$out" in
  *"no evidence of work"*) _bad "and not 'no evidence of work'" "$out" ;;
  *) _ok "and not 'no evidence of work'" ;;
esac

write_conf "$FIX" <<'EOF'
gate     | unit | required | . | { printf 'bash: frobnicate: command not found\n'; seq 1 300000; exit 127; }
evidence | unit | Tests +[1-9][0-9]* passed
EOF
out="$(gates)"
assert_contains "a launch failure on line 1 of 2 MB is BLOCKED, not FAIL" "BLOCKED      unit" "$out"

# Control: large output with no evidence line anywhere is still vacuous.
write_conf "$FIX" <<'EOF'
gate     | unit | required | . | { printf 'No test files found\n'; seq 1 300000; }
evidence | unit | Tests +[1-9][0-9]* passed
EOF
out="$(gates)"
assert_contains "2 MB with no evidence line is still no evidence of work" "no evidence of work" "$out"

# ---------------------------------------------------------------------------
describe "AC-3: no shell code pipes into a quiet grep"

# quiet_pipes <file>...   Prints `file:line: text` for every line of shell CODE
# that pipes into grep -q / -<cluster with q> / --quiet / --silent, either on the
# same line or after a `|` ending the previous line. Whole-line comments and
# heredoc bodies are data. A `<<WORD` only opens a heredoc if a line reading
# WORD follows it: a heredoc spelled inside a quoted string (phase-guard's
# fixtures are full of them) would otherwise swallow the rest of the file.
quiet_pipes() {
  awk '
    function flush(   i, j, w, strip, t, code, prevpipe, hit) {
      prevpipe = 0
      for (i = 1; i <= n; i++) {
        code = L[i]
        if (code ~ /^[ \t]*#/) continue
        hit = 0
        if (code ~ /(^|[^|])\|[ \t]*grep([ \t]+-[-A-Za-z0-9]+)*[ \t]+(-[A-Za-z]*q|--quiet|--silent)/) hit = 1
        if (prevpipe && code ~ /^[ \t]*grep([ \t]+-[-A-Za-z0-9]+)*[ \t]+(-[A-Za-z]*q|--quiet|--silent)/) hit = 1
        if (hit) printf "%s:%d: %s\n", F, i, code
        prevpipe = (code ~ /(^|[^|])\|[ \t]*\\?[ \t]*$/)
        if (match(code, /(^|[^<])<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
          w = substr(code, RSTART, RLENGTH)
          sub(/^[^<]?<</, "", w)
          strip = (w ~ /^-/); sub(/^-/, "", w); sub(/^[ \t]*["\047]?/, "", w)
          for (j = i + 1; j <= n; j++) {
            t = L[j]; if (strip) sub(/^\t+/, "", t)
            if (t == w) { i = j; prevpipe = 0; break }
          }
        }
      }
      n = 0
    }
    FNR == 1 && NR > 1 { flush() }
    FNR == 1 { F = FILENAME }
    { L[++n] = $0 }
    END { flush() }
  ' "$@"
}

PROBE="$(mktemp -d 2>/dev/null || mktemp -d -t pipes.XXXXXX)"
trap 'rm -rf "$FIX" "$PROBE"' EXIT

# Controls first: a scanner that flags nothing passes the real tree trivially.
cat > "$PROBE/bad.sh" <<'EOF'
printf '%s\n' "$x" | grep -qF -- y
if clean_log "$l" | grep -Eq -- "$p"; then :; fi
foo |
  grep -q bar
has_line() { printf '%s\n' "$1" | sed -e 's/\r$//' | grep -qE -- "$2"; }
EOF
got="$(quiet_pipes "$PROBE/bad.sh" | sed "s|^$PROBE/||")"
# Expected output goes in a heredoc. Spelled as a quoted string, it would be a
# line of code piping into a quiet grep, and this file would flag itself.
want="$(cat <<'EOF'
bad.sh:1: printf '%s\n' "$x" | grep -qF -- y
bad.sh:2: if clean_log "$l" | grep -Eq -- "$p"; then :; fi
bad.sh:4:   grep -q bar
bad.sh:5: has_line() { printf '%s\n' "$1" | sed -e 's/\r$//' | grep -qE -- "$2"; }
EOF
)"
assert_eq "the scanner flags every piped quiet grep" "$want" "$got"

cat > "$PROBE/good.sh" <<'EOF'
foo || grep -q bar
grep -q bar <<< "$x"
grep -Eq -- "$p" < <(clean_log "$l")
# a comment that says: printf | grep -q bar
  # indented: foo | grep -q bar
write_conf "$FIX" <<'CONF'
discovery | wide | . | seq 1 200000 | grep -q "^5$"
CONF
x="$(printf 'cat > f <<EOF\n')"   # a heredoc inside a string, never closed
out="$(foo | grep -c bar)"
EOF
got="$(quiet_pipes "$PROBE/good.sh")"
assert_eq "and nothing that is not one" "" "$got"

# A string that spells a heredoc must not blind the scanner to what follows.
cat > "$PROBE/after.sh" <<'EOF'
cmd="cat > src/x.ts <<'EOF2'"
printf '%s' "$y" | grep -q z
EOF
got="$(quiet_pipes "$PROBE/after.sh" | sed "s|^$PROBE/||")"
want="$(cat <<'EOF'
after.sh:2: printf '%s' "$y" | grep -q z
EOF
)"
assert_eq "an unclosed heredoc in a string does not hide the next line" "$want" "$got"

# The real tree.
cd "$REPO_ROOT" || exit 1
got="$(quiet_pipes scripts/*.sh .claude/tests/*.sh .claude/hooks/*.sh)"
assert_eq "scripts/, .claude/tests/ and .claude/hooks/ pipe into no quiet grep" "" "$got"

summary "pipe-readers"
