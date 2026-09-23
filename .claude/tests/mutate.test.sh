#!/usr/bin/env bash
# Tests for scripts/mutate.sh - the sanctioned diagnostic mutation.
#
# The harness requires mutations it did not provide a way to make. A test
# written or corrected while the implementation already exists passes on its
# first run and every run after, whether or not it asserts anything, and the
# only way to earn it is to break the production behaviour it claims to pin and
# watch that one assertion go red. rules.md demands that. rules.md also says
# never to route around the phase lock, and production source is frozen in RED,
# which is exactly when a corrected test needs earning.
#
# Every agent resolved that privately with `sed -i`, which the lock let through
# because it discarded any target containing `$`. Three source files were
# mutated that way in one corrective RED pass. And the one mutation done in a
# phase where source WAS writable lost its backup, because the shell it ran in
# had no $TMPDIR, so the restore depended on the substitution happening to be an
# exact inverse of a single-occurrence match. It was. That is the whole reason
# this script exists: the restore must be a fact, not a coincidence.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

FIX="$(make_project_fixture)"
trap 'rm -rf "$FIX"' EXIT

SRC="$FIX/src/main.ts"
ORIGINAL='export const clamp = (v) => Math.min(90, v)'

reset_src() { printf '%s\n' "$ORIGINAL" > "$SRC"; }

mutate() { ( cd "$FIX" && bash scripts/mutate.sh "$@" 2>&1 ); }

sha() { git -C "$FIX" hash-object "$1"; }

# --- what the piped cases at the end of this file need --------------------
#
# The helpers above cannot express them: mutate() is a command substitution,
# which reads to EOF and therefore never closes the pipe early, and closing the
# pipe early is the entire subject.

MUTDIR="$FIX/.claude/state/mutations"
LOG="$MUTDIR/log"
STFILE="$FIX/.mutate-pipestatus"

# A log line, anchored at BOTH ends. Every line mutate.sh writes opens with the
# same three tab-separated fields - stamp, file, expression - so this needle
# names THIS run and cannot be satisfied by a line about another file, another
# expression, or a stamp-shaped prefix of something else. It is counted, never
# searched for: "the log contains it" is as true of two lines as of one, and a
# fix that logs the same run twice has replaced a missing record with a lying
# one.
STAMP_RE='[0-9]{8}T[0-9]{6}Z'
RUN_LINE="^${STAMP_RE}"$'\t'"src/main\.ts"$'\t'"s/90/-90/("$'\t'".*)?$"
VERIFIED_LINE="^${STAMP_RE}"$'\t'"src/main\.ts"$'\t'"s/90/-90/"$'\t'".*"$'\t'"restored \(verified\)$"

# grep -c prints 0 and exits 1 when nothing matches, and prints nothing at all
# when the file is missing. Both have to read as 0, not as the empty string,
# or an assertion expecting "1" fails with a message that names the wrong cause.
count_lines() { local c; c="$(grep -cE "$1" "$LOG" 2>/dev/null)"; printf '%s' "${c:-0}"; }
count_files() { local c; c="$(ls "$MUTDIR" 2>/dev/null | grep -cE "\.$1\$")"; printf '%s' "${c:-0}"; }

# The NAMES of any leftovers rather than their number: when this fails, the
# message should say which pair was left behind.
leftovers() { ls "$MUTDIR" 2>/dev/null | grep -E '\.(bak|new)$' | tr '\n' ' '; }

# piped_run <N> <command...>
#
# mutate.sh with its MERGED output - `2>&1`, the shape an agent actually writes
# and the shape that produced this bug - piped into a reader that stops after N
# lines. Leaves what the reader let through in PIPED_OUT.
#
# PIPED_ST is mutate.sh's OWN status, from PIPESTATUS[0] read in the same shell
# as the pipeline. The pipeline's $? is the READER's, and head exits 0 even when
# the writer died of SIGPIPE; PIPESTATUS read outside a subshell that contains
# the pipeline reports the subshell. Either mistake hands back a clean exit for
# a probe that never happened, which is the hazard this story is about. Recorded
# rather than asserted: what mutate.sh's status is through a pipe is out of
# scope for this story, because a shell killed by SIGPIPE cannot choose it.
piped_run() {
  local n="$1"; shift
  PIPED_OUT="$( cd "$FIX" && { bash scripts/mutate.sh src/main.ts 's/90/-90/' -- "$@" 2>&1 | head -"$n"
                               printf '%s' "${PIPESTATUS[0]}" > "$STFILE"; } )"
  PIPED_ST="$(cat "$STFILE" 2>/dev/null)"
}

# Lines in a captured stream. printf '%s' rather than '%s\n' on purpose: an
# EMPTY capture must count 0, and `printf '%s\n' ""` would count it as 1 - which
# would let a run that printed nothing at all satisfy an assertion about how
# much a reader let through.
lines_in() { printf '%s' "$1" | grep -c ''; }

# ---------------------------------------------------------------------------
describe "the command sees the mutation"

reset_src
before="$(sha "$SRC")"
out="$(mutate src/main.ts 's/90/-90/' -- grep -c -- '-90' src/main.ts)"; rc=$?
assert_contains "the mutated file is what the command reads" "1" "$out"
assert_eq "and the command's exit code is passed through" "0" "$rc"
assert_eq "and the file is byte-identical afterwards" "$before" "$(sha "$SRC")"
assert_contains "and it says the restore was verified" "restored" "$out"
assert_contains "and prints the line it put back" "Math.min(90, v)" "$out"

# ---------------------------------------------------------------------------
describe "a failing command is the point, not an error"

# This is the shape the harness actually asks for: mutate the behaviour, watch
# the one assertion that pins it go red, revert. The red is the evidence, so a
# non-zero exit must not be treated as the script failing.
reset_src
before="$(sha "$SRC")"
out="$(mutate src/main.ts 's/90/-90/' -- sh -c 'exit 1')"; rc=$?
assert_eq "the command's failure is reported as its own" "1" "$rc"
assert_eq "and the file is still restored"               "$before" "$(sha "$SRC")"
assert_contains "and the exit code is stated plainly"    "exited 1" "$out"

# A command that cannot even start is not a reason to leave the tree mutated.
reset_src
before="$(sha "$SRC")"
mutate src/main.ts 's/90/-90/' -- no-such-command-here >/dev/null 2>&1
assert_eq "restored after a command that never ran" "$before" "$(sha "$SRC")"

# ---------------------------------------------------------------------------
describe "a mutation that mutates nothing proves nothing"

# An expression that matches nothing leaves the file identical, the command
# green, and the agent with a passing test it believes it has earned. That is
# worse than no probe at all, so it is refused before the command runs.
reset_src
before="$(sha "$SRC")"
rm -f "$FIX/ran-marker"
out="$(mutate src/main.ts 's/NOT_IN_THE_FILE/x/' -- touch ran-marker)"; rc=$?
assert_contains "it says the expression changed nothing" "changed nothing" "$out"
assert_eq "and exits 3"                                  "3" "$rc"
assert_eq "and the file is untouched"                    "$before" "$(sha "$SRC")"
if [ -e "$FIX/ran-marker" ]; then
  _bad "and the command never ran" "ran-marker exists"
else _ok "and the command never ran"; fi

# ---------------------------------------------------------------------------
describe "how much it changed is reported, because one line is the useful case"

reset_src
printf 'const a = 90\nconst b = 90\n' >> "$SRC"
out="$(mutate src/main.ts 's/90/-90/g' -- true)"
assert_contains "it counts the changed lines" "3 line(s)" "$out"
reset_src

# ---------------------------------------------------------------------------
describe "usage errors happen before anything is touched"

rm -f "$FIX/ran-marker"
out="$(mutate src/nope.ts 's/a/b/' -- touch ran-marker)"; rc=$?
assert_contains "a file that does not exist" "no such file" "$out"
assert_eq "exits 2"                          "2" "$rc"

out="$(mutate src/main.ts 's/90/-90/')"; rc=$?
assert_contains "no -- and no command" "-- <command>" "$out"
assert_eq "exits 2"                    "2" "$rc"

out="$(mutate src/main.ts 's/90/-90/' --)"; rc=$?
assert_contains "-- with nothing after it" "-- <command>" "$out"
assert_eq "exits 2"                        "2" "$rc"

out="$(mutate src/main.ts '' -- true)"; rc=$?
assert_contains "an empty expression" "expression" "$out"
assert_eq "exits 2"                   "2" "$rc"

if [ -e "$FIX/ran-marker" ]; then
  _bad "no command ran on any usage error" "ran-marker exists"
else _ok "no command ran on any usage error"; fi

# ---------------------------------------------------------------------------
describe "a restore that cannot be verified is loud, and keeps the backup"

# The one failure mode that must never be quiet. If the file cannot be put back
# byte-for-byte, an agent that reads "restored" and moves on has left a mutation
# in the tree with a green suite ahead of it.
reset_src
out="$(mutate src/main.ts 's/90/-90/' -- sh -c 'rm -f .claude/state/mutations/*.bak')"; rc=$?
assert_contains "it says the restore failed" "COULD NOT RESTORE" "$out"
assert_eq "and exits 90, whatever the command did" "90" "$rc"

# The same contract with a provocation the backup SURVIVES. The case above
# cannot show that half of it: its command deletes the .bak itself, so there is
# nothing left to keep and "the backup is kept" is unasserted. Here the command
# replaces the file with a directory, so the restoring `cp` lands inside it,
# `cmp` cannot verify anything, and the backup is still on disk to be kept or
# deleted.
#
# That is the negative control on the SHAPE of the fix, not decoration. An EXIT
# trap whose cleanup is unconditional - `rm -f "$NEW" "$BAK"` on every path -
# satisfies the piped cases at the end of this file completely and destroys the
# only signal the harness has for a failed restore. Exit 90 and the message
# below both survive that mutation; the two counts do not.
rm -rf "$MUTDIR"
rm -rf "$SRC"; reset_src
out="$(mutate src/main.ts 's/90/-90/' -- sh -c 'rm -f src/main.ts && mkdir src/main.ts')"; rc=$?
assert_eq "it exits 90 when the file cannot be put back" "90" "$rc"
assert_contains "and says which file"  "COULD NOT RESTORE" "$out"
assert_eq "and the backup is KEPT, which is what rules.md reads as the signal" \
  "1" "$(count_files bak)"
assert_eq "and only the .new working copy is removed" "0" "$(count_files new)"
rm -rf "$SRC"; reset_src
rm -rf "$MUTDIR"

# ---------------------------------------------------------------------------
describe "it refuses to mutate the script that is running"

# Found by using this script on this repository. bash reads a script
# incrementally rather than loading it whole, so rewriting mutate.sh while
# mutate.sh is executing changes what the interpreter reads next: the run dies
# somewhere in the middle and the restore - the last thing it does - never
# happens. The mutation is then left in the tree with nothing to say so, which
# is the exact failure this script exists to make impossible.
before="$(sha "$FIX/scripts/mutate.sh")"
out="$(mutate scripts/mutate.sh 's/ROOT=/R00T=/' -- true)"; rc=$?
assert_contains "it says why" "cannot mutate itself" "$out"
assert_eq "and exits 2"                   "2" "$rc"
assert_eq "and the script is untouched"   "$before" "$(sha "$FIX/scripts/mutate.sh")"

# The same by absolute path, which is how it would arrive from a script.
out="$(mutate "$FIX/scripts/mutate.sh" 's/ROOT=/R00T=/' -- true)"; rc=$?
assert_eq "an absolute path is the same file" "2" "$rc"
assert_eq "and still untouched"               "$before" "$(sha "$FIX/scripts/mutate.sh")"

# ---------------------------------------------------------------------------
describe "the log is what the story quotes"

reset_src
LOG="$FIX/.claude/state/mutations/log"
rm -f "$LOG"
mutate src/main.ts 's/90/-90/' -- sh -c 'exit 1' >/dev/null 2>&1
log="$(cat "$LOG" 2>/dev/null)"
assert_contains "the file"            "src/main.ts" "$log"
assert_contains "the expression"      "s/90/-90/"   "$log"
assert_contains "the command"         "exit 1"      "$log"
assert_contains "the command's code"  "exited 1"    "$log"
assert_contains "and the restore"     "restored"    "$log"

# ---------------------------------------------------------------------------
describe "it works with the phase lock on, in every phase"

# The point of the script. In RED source is frozen and this is still allowed,
# because the file it names is put back before the command that follows it.
for ph in RED GREEN GATES REVIEW; do
  set_phase "$FIX" "$ph"
  reset_src
  before="$(sha "$SRC")"
  mutate src/main.ts 's/90/-90/' -- true >/dev/null 2>&1
  assert_eq "restored in $ph" "$before" "$(sha "$SRC")"
done
set_phase "$FIX" ""


# ---------------------------------------------------------------------------
describe "a reader that closes the pipe early leaves no backup, and logs once"

# The bug. rules.md and .claude/state/README.md both say a leftover .bak means a
# restore FAILED and mutate.sh exited 90 saying so, and the "cannot be verified"
# case above is what makes that sentence true. Today `mutate ... 2>&1 | head -N`
# can leave the pair behind after a restore that SUCCEEDED and with no log line
# at all, so the harness's one signal for a broken tree fires when nothing is
# broken - and the next agent to meet a real leftover has been taught to
# discount it.
#
# The widths are swept rather than chosen. Where the pipe closes decides which
# line the SIGPIPE lands on, and the post-condition must not depend on that; the
# sweep also outlives the line numbering, which moves when the banners go to
# stderr. Measured at PLANNED and reproduced here at RED: no log line and a
# leftover pair at N <= 5, both clean at N = 6 and above.
#
# The log count is what keeps the leftover assertion honest. "No .bak is left"
# is an absence, and an absence is equally what a run that never happened
# produces; a log line naming this file and this expression can only come from
# this run.
for n in 1 2 3 4 5 6 30; do
  rm -rf "$MUTDIR"
  reset_src
  before="$(sha "$SRC")"
  piped_run "$n" touch ran-marker
  assert_eq "N=$n: no .bak or .new is left behind"      ""  "$(leftovers)"
  assert_eq "N=$n: exactly one log line names the run"  "1" "$(count_lines "$RUN_LINE")"
  assert_eq "N=$n: src/main.ts is byte-identical after" "$before" "$(sha "$SRC")"
done
rm -rf "$MUTDIR"; rm -f "$FIX/ran-marker"

# ---------------------------------------------------------------------------
describe "the sweep above really does close the pipe early"

# The instrument, not the subject. Every assertion in the sweep is about what
# survives a reader that stops reading. If the invocation quietly stopped
# truncating - piped_run rewritten as a command substitution, which is how every
# other case in this file runs - all twenty-one of them would keep passing and
# would have stopped testing anything at all. So the truncation itself is
# pinned: exactly one line through an N=1 pipe, and more than one line when
# nothing truncates.
rm -rf "$MUTDIR"; reset_src
piped_run 1 true
assert_eq "head -1 lets exactly one line through" "1" "$(lines_in "$PIPED_OUT")"
rm -rf "$MUTDIR"; reset_src
full="$(mutate src/main.ts 's/90/-90/' -- true)"
if [ "$(lines_in "$full")" -gt 1 ]; then
  _ok "and an untruncated run of the same command is longer than that"
else
  _bad "and an untruncated run of the same command is longer than that" "$full"
fi
rm -rf "$MUTDIR"

# ---------------------------------------------------------------------------
describe "an ordinary unpiped run still logs once and cleans up"

# Green before this story starts, and here so that a fix which moves the restore
# into a trap cannot quietly lose the path that already worked. Counted for the
# same reason as above: a trap that appends in ADDITION to the straight-line
# code shows up here as 2 and nowhere else.
rm -rf "$MUTDIR"; reset_src
before="$(sha "$SRC")"
mutate src/main.ts 's/90/-90/' -- true >/dev/null 2>&1
assert_eq "exactly one log line names the run"        "1" "$(count_lines "$RUN_LINE")"
assert_eq "and its outcome field is restored (verified)" "1" "$(count_lines "$VERIFIED_LINE")"
assert_eq "and no .bak or .new is left behind"        ""  "$(leftovers)"
assert_eq "and the file is byte-identical afterwards" "$before" "$(sha "$SRC")"
rm -rf "$MUTDIR"

# ---------------------------------------------------------------------------
describe "stdout is the command's output; mutate.sh's own goes to stderr"

# So that a caller can read stdout without killing the run - the idiom that
# produced the bug above - stdout must mean exactly one thing.
#
# Both halves are asserted, and the second half is why. "stdout holds no banner"
# is an absence, and it is satisfied just as well by a mutate.sh that prints
# nothing anywhere: that would delete the verdict `## Regressions` and
# `## Gate probes` are required to quote. So the payload is pinned as PRESENT on
# stdout, and the banner, the verdict and the restored line are pinned as
# PRESENT on stderr, in runs of the same command.
rm -rf "$MUTDIR"; reset_src
sout="$( cd "$FIX" && bash scripts/mutate.sh src/main.ts 's/90/-90/' \
           -- sh -c 'echo PAYLOAD-ON-STDOUT' 2>/dev/null )"
reset_src
serr="$( cd "$FIX" && bash scripts/mutate.sh src/main.ts 's/90/-90/' \
           -- sh -c 'echo PAYLOAD-ON-STDOUT' 2>&1 1>/dev/null )"
assert_contains "the command's own output is on stdout" "PAYLOAD-ON-STDOUT" "$sout"
assert_eq "and no === mutate: banner is" "0" "$(printf '%s\n' "$sout" | grep -c '=== mutate: ')"
assert_eq "and nothing else is either"   "PAYLOAD-ON-STDOUT" "$sout"
assert_contains "the banner is on stderr"     "=== mutate: " "$serr"
assert_contains "and so is the verdict"       "restored (verified byte-for-byte" "$serr"
assert_contains "and so is the line put back" "Math.min(90, v)" "$serr"
rm -rf "$MUTDIR"

summary "mutate"
