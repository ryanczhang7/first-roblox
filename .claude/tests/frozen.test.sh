#!/usr/bin/env bash
# Tests for scripts/frozen.sh - proving a frozen file was untouched (HARNESS-015).
#
# Every harness story before this one proved a phase respected the freeze by
# showing `git diff --stat <file>` empty. That is right at RED, where the frozen
# file is source and its last committed state is the previous merge. It is
# silently wrong at GREEN, where the frozen file is a TEST whose RED work is
# not committed: the diff is non-empty on every healthy GREEN, and the only way
# to make it empty is to revert the tests - the violation it was meant to catch.
#
# The check that works is the blob hash, recorded before the phase and compared
# after (`git hash-object`, HARNESS-014 Correction 1). frozen.sh makes that a
# two-verb tool:
#
#   bash scripts/frozen.sh snapshot <path>...   record, per active story
#   bash scripts/frozen.sh verify               compare, exit 0 only if equal
#
# So the one case that matters most here is AC-1: a file with an uncommitted
# change present THROUGHOUT, which git diff reports as changed and this tool
# must report as untouched. Every AC-1 case asserts that the diff really is
# non-empty at the moment verify runs, or it would not be testing that case.
#
# Needles. The three verdicts are mutually non-matching by design, and every
# one is matched as a WHOLE LINE and COUNTED, and every run asserts its exit
# status. The most likely vacuous test in this file is an AC-1 case that forgot
# to snapshot, got NO SNAPSHOT, and passed on a floating "OK": the exit status
# and the zero-count of the other verdicts are what stop it.
#
# Everything runs in a fixture repository (make_project_fixture), never against
# a story in the real docs/backlog/. The only two reads of the real checkout are
# in AC-6, and both are read-only: the state README's table row, and a run of
# settings.test.sh, which builds its own fixture.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

FIX="$(make_project_fixture)"
trap 'rm -rf "$FIX"' EXIT

DASH="$(printf '\342\200\224')"   # U+2014, as the Contract writes it

# --- helpers ----------------------------------------------------------------

# activate <STORY_ID> [PHASE]   The active story, in the shape phase.sh writes.
# Not set_phase: that hard-codes T-1, and AC-5 is about two different ids.
activate() {
  mkdir -p "$FIX/.claude/state"
  printf '# Written by scripts/phase.sh %s do not edit by hand.\nSTORY_ID=%s\nSTORY_SLUG=fixture\nSTORY_TYPE=fix\nPHASE=%s\nBRANCH=story/%s-fixture\nUPDATED=2026-09-23T00:00:00Z\n' \
    "$DASH" "$1" "${2:-GREEN}" "$1" > "$FIX/.claude/state/current-story.env"
}
deactivate() { rm -f "$FIX/.claude/state/current-story.env"; }

# reset_fixture   Back to the committed fixture with nothing in .claude/state.
# Cheaper than a fresh make_project_fixture per case, and just as clean: the
# fixture's own .gitignore does not cover .claude/state/, so `clean -x` takes
# every snapshot and the story file with it.
reset_fixture() {
  git -C "$FIX" reset -q --hard
  git -C "$FIX" clean -qfdx
  mkdir -p "$FIX/.claude/state"
}

# fz <args...>   Runs the fixture's frozen.sh from the fixture root. Leaves the
# merged output in OUT and the script's own exit status in ST.
fz() {
  OUT="$( cd "$FIX" && bash scripts/frozen.sh "$@" 2>&1 )"
  ST=$?
}

# Whole-line, fixed-string, counted. grep -c prints 0 on no match.
count_line() { printf '%s\n' "$OUT" | grep -cxF -- "$1"; }
# Anchored pattern, counted: for "how many verdicts of this kind at all".
count_re()   { printf '%s\n' "$OUT" | grep -cE -- "$1"; }

h() { git -C "$FIX" hash-object "$1"; }

ok_line()     { printf 'frozen: OK %s %s path(s) unchanged since the snapshot for %s' "$DASH" "$1" "$2"; }
changed_line(){ printf 'frozen: CHANGED %s %s: recorded %s, now %s' "$DASH" "$1" "$2" "$3"; }
nosnap_line() { printf 'frozen: NO SNAPSHOT %s nothing recorded for %s; take one before the phase starts' "$DASH" "$1"; }
NOSTORY_LINE="frozen: NO STORY ${DASH} no active story (.claude/state/current-story.env is missing); start one with bash scripts/phase.sh set <ID> <PHASE>"

OK_RE='^frozen: OK '
CHANGED_RE='^frozen: CHANGED '
NOSNAP_RE='^frozen: NO SNAPSHOT '

# previous_phase_edit   The state every GREEN starts in: RED's work on the
# frozen files is on disk and NOT committed. One tracked file modified, one new
# test file untracked - git diff shows the first and cannot see the second.
previous_phase_edit() {
  printf 'export const x = 1\nexport const fromRed = 2\n' > "$FIX/src/main.ts"
  printf 'test("added in RED", () => {})\n' > "$FIX/tests/red.test.ts"
}

# diff_nonempty <path>   0 when git diff says the path differs from the index.
# `git diff --quiet` exits 1 on a difference, so this inverts it into "yes".
diff_nonempty() { ! git -C "$FIX" diff --quiet -- "$1" 2>/dev/null; }

# fingerprint   Everything outside .claude/state/ that a script could write:
# every file's content hash and every directory's existence (ignored ones too -
# git status would not see a write under the fixture's ignored dist/), the
# index's staged content, HEAD, and the object count, which is what
# `git hash-object -w` would move. The raw .git/index is deliberately NOT
# hashed: git status itself refreshes it, and that is not frozen.sh writing.
fingerprint() {
  ( cd "$FIX" || exit 1
    find . \( -path ./.git -o -path ./.claude/state \) -prune -o -type d -print | LC_ALL=C sort | sed 's/^/dir /'
    find . \( -path ./.git -o -path ./.claude/state \) -prune -o -type f -print | LC_ALL=C sort > "$FIX/.git/fp-list"
    paste -d' ' - "$FIX/.git/fp-list" < <(git hash-object --stdin-paths < "$FIX/.git/fp-list")
    rm -f "$FIX/.git/fp-list"
    git status --porcelain --untracked-files=all 2>/dev/null | grep -v '\.claude/state/'
    git ls-files -s
    git rev-parse HEAD
    git count-objects
  )
}

# ---------------------------------------------------------------------------
describe "the script under test exists in the fixture"

# Not an AC. Here so that the first failure in RED says what is missing in one
# line, rather than leaving it to be inferred from exit 127 in every case below.
if [ -f "$FIX/scripts/frozen.sh" ]; then _ok "scripts/frozen.sh is present"
else _bad "scripts/frozen.sh is present" "no such file in the fixture (copied from $REPO_ROOT/scripts at fixture creation)"; fi

# ---------------------------------------------------------------------------
describe "AC-1: a file with an uncommitted change from the previous phase, untouched since the snapshot, verifies as unchanged"

reset_fixture; activate HX-1
previous_phase_edit
fz snapshot src/main.ts
assert_eq "snapshot of an uncommitted-modified file exits 0" "0" "$ST"
# The case git diff gets wrong must be the case under test, at the moment of verify.
if diff_nonempty src/main.ts; then _ok "precondition: git diff for src/main.ts is NON-empty when verify runs"
else _bad "precondition: git diff for src/main.ts is NON-empty when verify runs" "the diff is empty, so this case does not test what git diff gets wrong"; fi
fz verify
assert_eq "verify exits 0 when the frozen file is untouched, despite its non-empty git diff" "0" "$ST"
assert_eq "verify prints exactly one OK line naming 1 path and the active story" "1" "$(count_line "$(ok_line 1 HX-1)")"
assert_eq "verify prints no CHANGED line for an untouched file" "0" "$(count_re "$CHANGED_RE")"
assert_eq "verify does not report NO SNAPSHOT after a snapshot was taken" "0" "$(count_re "$NOSNAP_RE")"

# Many: a tracked file with an uncommitted change AND a new untracked test file
# RED created, both frozen together.
reset_fixture; activate HX-1
previous_phase_edit
fz snapshot src/main.ts tests/red.test.ts
assert_eq "snapshot of two paths exits 0" "0" "$ST"
if diff_nonempty src/main.ts; then _ok "precondition: git diff for src/main.ts is still NON-empty"
else _bad "precondition: git diff for src/main.ts is still NON-empty" "the diff is empty"; fi
fz verify
assert_eq "verify of two untouched paths exits 0" "0" "$ST"
assert_eq "the OK line counts both paths" "1" "$(count_line "$(ok_line 2 HX-1)")"
assert_eq "no CHANGED line when neither frozen path moved" "0" "$(count_re "$CHANGED_RE")"

# Content, not timestamps: rewriting a file with identical bytes is not a change.
reset_fixture; activate HX-1
previous_phase_edit
fz snapshot src/main.ts
printf 'scribble\n' > "$FIX/src/main.ts"
printf 'export const x = 1\nexport const fromRed = 2\n' > "$FIX/src/main.ts"
fz verify
assert_eq "a file rewritten back to identical content verifies as unchanged (hash, not mtime)" "0" "$ST"
assert_eq "and says OK for 1 path" "1" "$(count_line "$(ok_line 1 HX-1)")"

# ---------------------------------------------------------------------------
describe "AC-2: a frozen file modified after the snapshot fails verify, naming the path and both hashes"

reset_fixture; activate HX-1
previous_phase_edit
OLD="$(h src/main.ts)"
fz snapshot src/main.ts
printf 'export const x = 1\nexport const fromRed = 2\nexport const fromGreen = 3\n' > "$FIX/src/main.ts"
NEW="$(h src/main.ts)"
if [ -n "$OLD" ] && [ -n "$NEW" ] && [ "$OLD" != "$NEW" ]; then _ok "precondition: the recorded and current hashes differ"
else _bad "precondition: the recorded and current hashes differ" "old=$OLD new=$NEW"; fi
fz verify
assert_eq "verify exits 1 when a frozen file changed after the snapshot" "1" "$ST"
assert_eq "verify prints the CHANGED line with the path, the recorded hash and the current hash" \
  "1" "$(count_line "$(changed_line src/main.ts "$OLD" "$NEW")")"
assert_eq "exactly one CHANGED line for one changed path" "1" "$(count_re "$CHANGED_RE")"
assert_eq "verify prints no OK line when a frozen file changed" "0" "$(count_re "$OK_RE")"

# One of many: only the path that moved is reported.
reset_fixture; activate HX-1
previous_phase_edit
OLD_T="$(h tests/red.test.ts)"
fz snapshot src/main.ts tests/red.test.ts
printf 'test("weakened in GREEN", () => {})\n' > "$FIX/tests/red.test.ts"
NEW_T="$(h tests/red.test.ts)"
fz verify
assert_eq "verify exits 1 when one of two frozen paths changed" "1" "$ST"
assert_eq "the changed untracked test file is named with both hashes" \
  "1" "$(count_line "$(changed_line tests/red.test.ts "$OLD_T" "$NEW_T")")"
assert_eq "the untouched path is not reported as changed" "1" "$(count_re "$CHANGED_RE")"
assert_eq "no OK line when any frozen path changed" "0" "$(count_re "$OK_RE")"

# Both changed: one line each, so the count is the number of divergences.
reset_fixture; activate HX-1
previous_phase_edit
fz snapshot src/main.ts tests/red.test.ts
printf 'a\n' >> "$FIX/src/main.ts"
printf 'b\n' >> "$FIX/tests/red.test.ts"
fz verify
assert_eq "verify exits 1 when both frozen paths changed" "1" "$ST"
assert_eq "one CHANGED line per changed path" "2" "$(count_re "$CHANGED_RE")"

# ---------------------------------------------------------------------------
describe "AC-3: verify with no snapshot for the active story refuses, and does not exit 0"

reset_fixture; activate HX-3
previous_phase_edit
fz verify
assert_eq "verify with no snapshot exits 1" "1" "$ST"
assert_eq "verify with no snapshot prints the NO SNAPSHOT line for the active story" "1" "$(count_line "$(nosnap_line HX-3)")"
assert_eq "verify with no snapshot prints no OK line" "0" "$(count_re "$OK_RE")"
assert_eq "verify with no snapshot prints no CHANGED line" "0" "$(count_re "$CHANGED_RE")"

# ---------------------------------------------------------------------------
describe "AC-4: a path absent at snapshot time and created before verify is reported as added"

reset_fixture; activate HX-4
previous_phase_edit
[ -e "$FIX/tests/later.test.ts" ] && _bad "precondition: tests/later.test.ts is absent at snapshot" "it exists" \
  || _ok "precondition: tests/later.test.ts is absent at snapshot"
fz snapshot tests/later.test.ts
assert_eq "snapshot of an absent path exits 0" "0" "$ST"
printf 'test("created in a phase that froze it", () => {})\n' > "$FIX/tests/later.test.ts"
ADDED="$(h tests/later.test.ts)"
fz verify
assert_eq "verify exits 1 when a frozen-absent path now exists" "1" "$ST"
assert_eq "the CHANGED line records ABSENT, the new hash, and (added)" \
  "1" "$(count_line "$(changed_line tests/later.test.ts ABSENT "$ADDED") (added)")"
assert_eq "exactly one CHANGED line" "1" "$(count_re "$CHANGED_RE")"
assert_eq "no OK line when a frozen-absent path appeared" "0" "$(count_re "$OK_RE")"

# Contract case, not an AC: absence frozen and still absent is unchanged.
reset_fixture; activate HX-4
fz snapshot tests/later.test.ts
fz verify
assert_eq "[contract] a path absent at snapshot and still absent verifies as unchanged (exit 0)" "0" "$ST"
assert_eq "[contract] and says OK for 1 path" "1" "$(count_line "$(ok_line 1 HX-4)")"

# Contract case, not an AC: the pinned mirror of (added).
reset_fixture; activate HX-4
previous_phase_edit
GONE="$(h tests/red.test.ts)"
fz snapshot tests/red.test.ts
rm -f "$FIX/tests/red.test.ts"
fz verify
assert_eq "[contract] verify exits 1 when a frozen file was deleted" "1" "$ST"
assert_eq "[contract] the CHANGED line records the old hash, ABSENT, and (deleted)" \
  "1" "$(count_line "$(changed_line tests/red.test.ts "$GONE" ABSENT) (deleted)")"
assert_eq "[contract] no OK line when a frozen file was deleted" "0" "$(count_re "$OK_RE")"

# ---------------------------------------------------------------------------
describe "AC-5: a snapshot taken for story A does not answer for story B"

# A's record would say OK if consulted: the file is untouched throughout. So an
# implementation that ignored the story id - reading any frozen-*.tsv, or a
# single shared file - would exit 0 here, and this case bites exactly that.
reset_fixture; activate HX-A
previous_phase_edit
fz snapshot src/main.ts
assert_eq "snapshot for story A exits 0" "0" "$ST"
activate HX-B
fz verify
assert_eq "verify under story B, with only A's snapshot on disk, exits 1" "1" "$ST"
assert_eq "it prints NO SNAPSHOT naming story B" "1" "$(count_line "$(nosnap_line HX-B)")"
assert_eq "it does not print NO SNAPSHOT naming story A" "0" "$(count_line "$(nosnap_line HX-A)")"
assert_eq "it prints no OK line - A's record did not answer for B" "0" "$(count_re "$OK_RE")"
assert_eq "it prints no CHANGED line - A's record was not compared at all" "0" "$(count_re "$CHANGED_RE")"
# The negative control, executed: A's record, consulted under A, does say OK.
# Without this, "B refused" could be "the record was unusable for anyone".
activate HX-A
fz verify
assert_eq "control: back under story A, the same record verifies OK (exit 0)" "0" "$ST"
assert_eq "control: and the OK line names story A" "1" "$(count_line "$(ok_line 1 HX-A)")"

# ---------------------------------------------------------------------------
describe "[contract] the snapshot file: where it lives, what it holds, and that it is replaced"

reset_fixture; activate HX-C
previous_phase_edit
fz snapshot src/main.ts
if [ -f "$FIX/.claude/state/frozen-HX-C.tsv" ]; then _ok "[contract] snapshot writes .claude/state/frozen-<STORY_ID>.tsv"
else _bad "[contract] snapshot writes .claude/state/frozen-<STORY_ID>.tsv" "$(ls -A "$FIX/.claude/state" 2>&1)"; fi
assert_eq "[contract] one row per path: <path><TAB><git hash-object>" \
  "$(printf 'src/main.ts\t%s' "$(h src/main.ts)")" "$(cat "$FIX/.claude/state/frozen-HX-C.tsv" 2>/dev/null)"

fz snapshot tests/main.test.ts tests/absent.test.ts
assert_eq "[contract] a second snapshot for the same story replaces the first, rows in argument order, ABSENT for a missing path" \
  "$(printf 'tests/main.test.ts\t%s\ntests/absent.test.ts\tABSENT' "$(h tests/main.test.ts)")" \
  "$(cat "$FIX/.claude/state/frozen-HX-C.tsv" 2>/dev/null)"
# Behaviourally too: the path dropped from the snapshot is no longer frozen.
printf 'moved after the re-snapshot\n' >> "$FIX/src/main.ts"
fz verify
assert_eq "[contract] after re-snapshot, a path only the FIRST snapshot named is not checked (exit 0)" "0" "$ST"
assert_eq "[contract] and the OK line counts the second snapshot's 2 paths, not 3" "1" "$(count_line "$(ok_line 2 HX-C)")"

# ---------------------------------------------------------------------------
describe "[contract] refusals outside the criteria: no active story, no paths, no such verb"

reset_fixture; deactivate
fz verify
assert_eq "[contract] verify with no active story exits 1" "1" "$ST"
assert_eq "[contract] verify with no active story prints the NO STORY line" "1" "$(count_line "$NOSTORY_LINE")"
assert_eq "[contract] verify with no active story prints no OK line" "0" "$(count_re "$OK_RE")"

fz snapshot src/main.ts
assert_eq "[contract] snapshot with no active story exits 1" "1" "$ST"
assert_eq "[contract] snapshot with no active story prints the NO STORY line" "1" "$(count_line "$NOSTORY_LINE")"
assert_eq "[contract] snapshot with no active story writes no frozen-*.tsv" \
  "0" "$(ls "$FIX/.claude/state" 2>/dev/null | grep -c '^frozen-')"

reset_fixture; activate HX-U
fz snapshot
assert_eq "[contract] snapshot with no paths is a usage error (exit 2)" "2" "$ST"
assert_eq "[contract] snapshot with no paths writes no frozen-*.tsv" \
  "0" "$(ls "$FIX/.claude/state" 2>/dev/null | grep -c '^frozen-')"
fz
assert_eq "[contract] no verb is a usage error (exit 2)" "2" "$ST"
fz fix
assert_eq "[contract] there is no third verb: 'fix' is a usage error (exit 2)" "2" "$ST"
assert_eq "[contract] and an unknown verb prints no OK line" "0" "$(count_re "$OK_RE")"

# ---------------------------------------------------------------------------
describe "AC-6: frozen.sh writes nothing outside .claude/state/ and never modifies a frozen path"

reset_fixture; activate HX-6
previous_phase_edit
# expect_untouched <label> <frozen.sh args...>
expect_untouched() {
  local label="$1" before after; shift
  before="$(fingerprint)"
  fz "$@"
  after="$(fingerprint)"
  if [ -n "$before" ] && [ "$before" = "$after" ]; then _ok "$label"
  else _bad "$label" "$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -20)"; fi
}
# The instrument first. Every expect_untouched below passes in RED, because
# frozen.sh does not exist and a missing script writes nothing - so on its own
# each is green on arrival and could be comparing two empty strings. These
# controls run NOW, against no frozen.sh at all, and show the fingerprint moves
# for each kind of write AC-6 forbids and stays still for the one it permits.
fp_moves() { # <label> <yes|no> <command run in the fixture>
  local before after moved
  before="$(fingerprint)"; ( cd "$FIX" && eval "$3" ) >/dev/null 2>&1; after="$(fingerprint)"
  if [ "$before" != "$after" ]; then moved=yes; else moved=no; fi
  assert_eq "control: the fingerprint $( [ "$2" = yes ] && echo moves || echo 'does not move') for $1" "$2" "$moved"
}
fp_moves "a write to a frozen tracked file"            yes 'printf x >> src/main.ts'
fp_moves "rewriting a frozen file with the same bytes" no  'cp src/main.ts src/main.ts.tmp && mv src/main.ts.tmp src/main.ts'
fp_moves "a new file under a gitignored directory"     yes 'mkdir -p dist && printf x > dist/leak'
fp_moves "a new empty directory"                       yes 'mkdir -p leakdir'
fp_moves "staging a file (git add)"                    yes 'git add tests/red.test.ts'
fp_moves "writing a blob (git hash-object -w)"         yes 'printf "unique %s" "$RANDOM$RANDOM" > .claude/state/blob && git hash-object -w .claude/state/blob'
fp_moves "a write under .claude/state/"                no  'printf x > .claude/state/frozen-HX-6.tsv.scratch'
reset_fixture; activate HX-6
previous_phase_edit

expect_untouched "snapshot (tracked-modified, untracked and absent paths) leaves the tree outside .claude/state/ unchanged" \
  snapshot src/main.ts tests/red.test.ts tests/absent.test.ts
expect_untouched "verify, OK, leaves the tree unchanged" verify
printf 'moved\n' >> "$FIX/src/main.ts"
expect_untouched "verify, CHANGED, leaves the tree unchanged - it does not restore or stage the file" verify
activate HX-6-other
expect_untouched "verify, NO SNAPSHOT, leaves the tree unchanged" verify
expect_untouched "snapshot with no paths leaves the tree unchanged" snapshot
deactivate
expect_untouched "snapshot with no active story leaves the tree unchanged" snapshot src/main.ts
expect_untouched "verify with no active story leaves the tree unchanged" verify

describe "AC-6: the new state file is in the real .claude/state/README.md table, and settings.test.sh still passes"

# The real README, read-only. First cell spelled as the Contract pins it: a
# glob, like the table's `gate-logs/*.log` and `mutations/*.bak`, because one
# file exists per story. Hand-editable `no`: see the Contract for why.
ROW_RE='^\| `frozen-\*\.tsv` \| `scripts/frozen\.sh` \|.*\| no \|$'
assert_eq "README has exactly one row: | \`frozen-*.tsv\` | \`scripts/frozen.sh\` | ... | no |" \
  "1" "$(grep -cE -- "$ROW_RE" "$REPO_ROOT/.claude/state/README.md")"
# That row saying `no`, and this suite passing, together mean settings.json
# carries the Write/Edit/MultiEdit deny rules for it: settings.test.sh fails a
# `no` row without them (its own "a no row with no rule" case).
SETTINGS_OUT="$(bash "$REPO_ROOT/.claude/tests/settings.test.sh" 2>&1)"; SETTINGS_ST=$?
assert_eq "bash .claude/tests/settings.test.sh exits 0" "0" "$SETTINGS_ST"
[ "$SETTINGS_ST" -eq 0 ] || printf '%s\n' "$SETTINGS_OUT" | tail -15 | sed 's/^/         | /'

summary "frozen"
