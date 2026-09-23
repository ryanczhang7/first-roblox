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

# --- what the early-exit cases need (HARNESS-013) ---------------------------
#
# The two paths that exit ABOVE the finish() trap - sed rejected the
# expression (exit 2) and the expression changed nothing (exit 3) - print first
# and clean up afterwards. piped_run cannot reach them: its expression is
# hardwired to s/90/-90/ and its reader is always head -N, and two of the four
# readers these cases sweep are not head -N at all.

# piped_expr_run <READER> <EXPR> <command...>
#
# The sibling of piped_run, with the expression and the reader as arguments.
# READER is a command word list - 'head -0', 'head -4', 'true' - split on
# whitespace at the point of use. Same merged stream (2>&1: the shape an agent
# writes, and after HARNESS-012 the only shape that still sends these paths'
# output down the pipe at all), same scratch-file capture of PIPESTATUS[0] in
# the same shell as the pipeline, same PIPED_OUT / PIPED_ST, and PIPED_ST is
# still recorded and never asserted: mutate.sh's status through a pipe is out
# of scope, because a shell killed by SIGPIPE cannot choose it.
piped_expr_run() {
  local reader="$1" expr="$2"; shift 2
  # shellcheck disable=SC2086  # $reader is split on purpose: it is a word list
  PIPED_OUT="$( cd "$FIX" && { bash scripts/mutate.sh src/main.ts "$expr" -- "$@" 2>&1 | $reader
                               printf '%s' "${PIPESTATUS[0]}" > "$STFILE"; } )"
  PIPED_ST="$(cat "$STFILE" 2>/dev/null)"
}

# EVERYTHING under the mutations directory except the log, by name. Not
# leftovers(): its pattern is \.(bak|new)$, and the sed-rejected path leaves a
# third file, `.new.err`, that the pattern cannot see - and an assertion that
# cannot see the file it is about is a needle that cannot fail. Empty means
# clean; anything else is what was left behind, named.
entries_but_log() { ls "$MUTDIR" 2>/dev/null | grep -v '^log$' | tr '\n' ' '; }

# Whole-line matches in a captured stream, for the messages the early-exit
# paths print: -x so that a line is matched entire, -F so that the message is
# quoted rather than turned into a pattern. Counted, so that a line printed
# twice or not at all reads as 2 or 0 rather than "contains".
count_exact() { printf '%s\n' "$1" | grep -cxF -- "$2"; }

# The changed-nothing line, anchored at both ends against the three leading
# tab-separated fields and the verbatim outcome. Counted, never searched for.
NOTHING_LINE="^${STAMP_RE}"$'\t'"src/main\.ts"$'\t'"s/NOT_IN_THE_FILE/x/"$'\t'"CHANGED NOTHING - command not run$"

# The line the sed-rejected path must NOT write. s/90/-90 (unterminated) is a
# proper prefix of the ordinary expression s/90/-90/, so a floating needle for
# this absence counts the ORDINARY path's log line and reports a leak that is
# not there. The trailing (\t.*)?$ is load-bearing: the expression field ends
# at a tab or at end of line, never at a slash. Demonstrated to count 0 beside
# an ordinary line in "the needle for the rejected path does not match the
# ordinary one" below.
REJECTED_LINE="^${STAMP_RE}"$'\t'"src/main\.ts"$'\t'"s/90/-90("$'\t'".*)?$"

# The four readers every early-exit case is swept through. The first two close
# the pipe before reading a byte; the last two are the widths that already
# pass, swept rather than dropped so that a fix cannot hold at one end by
# breaking the other. Measured at PLANNED, reproduced independently at
# PLANNED->RED, read out here rather than re-derived.
EARLY_READERS=('head -0' 'true' 'head -1' 'head -4')

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
describe "and says so in full: the whole explanation, on stderr, before exit 3"

# HARNESS-013 AC-6. The block above pins "changed nothing" as a substring and
# nothing about the rest of the explanation; this one pins all four lines, each
# matched entire, on the stream they belong to. It sits beside the block above
# rather than replacing it because the two are meant to differ: delete one of
# the four printfs and this block goes red while "it says the expression
# changed nothing" stays green. That contrast is what shows this is sharper
# than a restatement.
#
# Green before this story starts. It is the contract the reorder must not
# break: the fix moves the log append and the rm above these four printfs, and
# a reorder that dropped or garbled a line would satisfy every file assertion
# in this suite and change only what the agent is told.
reset_src
before="$(sha "$SRC")"
rm -f "$FIX/ran-marker"
err="$( cd "$FIX" && bash scripts/mutate.sh src/main.ts 's/NOT_IN_THE_FILE/x/' -- touch ran-marker 2>&1 1>/dev/null )"; rc=$?
assert_eq "unpiped, it still exits 3" "3" "$rc"
assert_eq "line 1 of 4 is on stderr, entire" "1" \
  "$(count_exact "$err" 'mutate: the expression changed nothing in src/main.ts.')"
assert_eq "line 2 of 4 is on stderr, entire" "1" \
  "$(count_exact "$err" '  A probe that does not alter behaviour cannot show a test discriminates:')"
assert_eq "line 3 of 4 is on stderr, entire" "1" \
  "$(count_exact "$err" '  the command would have passed for the same reason it passes now. Check the')"
assert_eq "line 4 of 4 is on stderr, entire" "1" \
  "$(count_exact "$err" '  expression against the file and try again.')"
assert_eq "and src/main.ts is byte-identical" "$before" "$(sha "$SRC")"
if [ -e "$FIX/ran-marker" ]; then
  _bad "and the command never ran" "ran-marker exists"
else _ok "and the command never ran"; fi
rm -f "$FIX/ran-marker"

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

# ===========================================================================
# HARNESS-013: the two paths that exit ABOVE the trap.
#
# HARNESS-012 moved the restore, the log append and the clean-up into an EXIT
# trap installed before the first byte is printed - for every path that reaches
# the trap. Two do not: sed rejecting the expression (exit 2) and the
# expression changing nothing (exit 3) both print first and clean up after, so
# a reader that closes the pipe before ANY byte gets through kills the shell at
# the first printf and leaves the backup, the working copy and (on the exit 2
# path) the .err file behind with no log line - the exact false alarm
# HARNESS-012 removed, on two paths where nothing was ever mutated.
#
# `head -30` never trips this: both blocks print two to four short lines, which
# fit the pipe buffer. It takes `head -0`, or a reader that exits without
# reading. So the four readers below are the story's, read out rather than
# re-derived; `head -1` and `head -4` pass today and are swept so a fix cannot
# hold at one end by breaking the other. Every log assertion is a COUNT with
# a needle anchored at both ends. The command is `true` throughout, because
# neither path reaches it.
# ===========================================================================

# ---------------------------------------------------------------------------
describe "an expression that changes nothing leaves no backup through a closed pipe, and logs once"

# AC-1 and AC-2. The post-condition at every reader: the mutations directory
# holds the log and nothing else, and the log holds exactly one line for this
# run - file, expression, and the verbatim outcome. Enumerated and counted:
# "no .bak" is an absence, and an absence is equally what a run that died
# before touching anything produces; the one log line can only come from this
# run. Today the head -0 and true rows leave a .bak/.new pair and no log file.
for reader in "${EARLY_READERS[@]}"; do
  rm -rf "$MUTDIR"
  reset_src
  before="$(sha "$SRC")"
  piped_expr_run "$reader" 's/NOT_IN_THE_FILE/x/' true
  assert_eq "reader '$reader': nothing but the log is left under mutations/" \
    "" "$(entries_but_log)"
  assert_eq "reader '$reader': exactly one log line says CHANGED NOTHING - command not run" \
    "1" "$(count_lines "$NOTHING_LINE")"
  assert_eq "reader '$reader': src/main.ts is byte-identical after" \
    "$before" "$(sha "$SRC")"
done
rm -rf "$MUTDIR"

# ---------------------------------------------------------------------------
describe "an expression sed rejects leaves no backup, no working copy and no .err through a closed pipe"

# AC-3 and AC-4. This path leaves one file MORE than the other - the .new.err
# that sed's complaint was captured into - which is why the directory is
# enumerated rather than pattern-matched. And this path writes NO log line, by
# decision (PO decision 2): the count of lines naming this expression is zero
# at every reader. Today the head -0 and true rows leave all three files.
for reader in "${EARLY_READERS[@]}"; do
  rm -rf "$MUTDIR"
  reset_src
  before="$(sha "$SRC")"
  piped_expr_run "$reader" 's/90/-90' true
  assert_eq "reader '$reader': nothing but the log is left under mutations/ - no .bak, .new or .new.err" \
    "" "$(entries_but_log)"
  assert_eq "reader '$reader': no log line names the rejected expression" \
    "0" "$(count_lines "$REJECTED_LINE")"
  assert_eq "reader '$reader': src/main.ts is byte-identical after" \
    "$before" "$(sha "$SRC")"
done

# The control on that zero, and AC-5 with it. A count of 0 is also what a
# missing or unwritable log produces, so in ONE directory: a changed-nothing
# run first, which must leave its one line - proof the log is there and takes
# writes - then the rejected expression unpiped, which must add none.
rm -rf "$MUTDIR"; reset_src
mutate src/main.ts 's/NOT_IN_THE_FILE/x/' -- true >/dev/null 2>&1
assert_eq "control: a changed-nothing run in the same directory logs its one line" \
  "1" "$(count_lines "$NOTHING_LINE")"

# What sed itself says about this expression, measured directly, so that the
# assertion below quotes THIS machine's sed rather than a transcript of one.
# Non-empty is asserted first: an empty complaint would make "  " the needle.
sed_complaint="$( cd "$FIX" && sed -e 's/90/-90' src/main.ts 2>&1 >/dev/null | head -1 )"
if [ -n "$sed_complaint" ]; then _ok "sed's own complaint about s/90/-90 is non-empty"
else _bad "sed's own complaint about s/90/-90 is non-empty" "sed printed nothing on stderr"; fi

before="$(sha "$SRC")"
err="$( cd "$FIX" && bash scripts/mutate.sh src/main.ts 's/90/-90' -- true 2>&1 1>/dev/null )"; rc=$?
# AC-5. The negative control on the SHAPE of the fix: the second line below is
# rendered from $NEW.err, and the reorder deletes that file before printing. A
# fix that moves the rm up without first capturing the text keeps every file
# assertion above green and silently drops the only line that says WHY the
# expression was refused.
assert_eq "unpiped, the rejected expression still exits 2" "2" "$rc"
assert_eq "and stderr carries the heading, entire" \
  "1" "$(count_exact "$err" 'mutate: sed rejected the expression:')"
assert_eq "and sed's own complaint, indented by two spaces" \
  "1" "$(count_exact "$err" "  $sed_complaint")"
assert_eq "and src/main.ts is byte-identical after" "$before" "$(sha "$SRC")"
# AC-4, the unpiped run, against a log that is present and writable.
assert_eq "and still no log line names the rejected expression" \
  "0" "$(count_lines "$REJECTED_LINE")"
assert_eq "while the control's line is still the only one in the log" \
  "1" "$(grep -c '' "$LOG" 2>/dev/null)"
assert_eq "and nothing but the log is left under mutations/" "" "$(entries_but_log)"
rm -rf "$MUTDIR"

# ---------------------------------------------------------------------------
describe "the ordinary mutating run stays clean at the readers that close the pipe unread"

# AC-7. HARNESS-012's fix, at the two readers its sweep did not use - head -0
# and true, which close the pipe before the banner - and at two it did. Green
# today; written down here so that a story reordering the code above the trap
# cannot quietly undo it, and earned by moving the trap back below the banner
# (deferred verification 6), which must turn the head -0 and true rows red.
for reader in "${EARLY_READERS[@]}"; do
  rm -rf "$MUTDIR"
  reset_src
  before="$(sha "$SRC")"
  piped_expr_run "$reader" 's/90/-90/' true
  assert_eq "reader '$reader': nothing but the log is left under mutations/" \
    "" "$(entries_but_log)"
  assert_eq "reader '$reader': exactly one log line names the run" \
    "1" "$(count_lines "$RUN_LINE")"
  assert_eq "reader '$reader': src/main.ts is byte-identical after" \
    "$before" "$(sha "$SRC")"
done

# ---------------------------------------------------------------------------
describe "the needle for the rejected path does not match the ordinary one"

# The instrument, not the subject. s/90/-90 is a proper prefix of s/90/-90/,
# so a needle for the rejected expression that floats - or that anchors only
# at the front - counts the ORDINARY path's line and reports a leak that is not
# there. The log left by the sweep above holds one ordinary line; a
# changed-nothing run is added to it, and the three anchored needles must then
# read 1, 1 and 0 against a log of exactly two lines. The floating count is
# asserted too, at 1: it is the false alarm the anchor prevents, and if it ever
# reads 0 the log no longer contains the prefix and the demonstration is empty.
reset_src
mutate src/main.ts 's/NOT_IN_THE_FILE/x/' -- true >/dev/null 2>&1
assert_eq "the log holds exactly two lines" "2" "$(grep -c '' "$LOG" 2>/dev/null)"
assert_eq "RUN_LINE counts the ordinary run once"        "1" "$(count_lines "$RUN_LINE")"
assert_eq "NOTHING_LINE counts the changed-nothing run once" "1" "$(count_lines "$NOTHING_LINE")"
assert_eq "REJECTED_LINE, anchored, counts zero beside them" "0" "$(count_lines "$REJECTED_LINE")"
assert_eq "whereas a floating grep -F for s/90/-90 would count the ordinary line" \
  "1" "$(grep -cF 's/90/-90' "$LOG" 2>/dev/null)"
rm -rf "$MUTDIR"

summary "mutate"
