#!/usr/bin/env bash
# Tests for scripts/classify.sh - the path classifier, reachable from test code
# written in any language.
#
# Why this script exists. `classify` is a bash function in .claude/hooks/lib.sh,
# so the only consumer that could reach it was another bash script - which meant
# a project's own guards, written in the project's language, rolled their own
# idea of "a source module" in a private regex. One project ended up with FOUR
# private copies, two of which had drifted apart, and all four were returning
# deliberately-offending probe artifacts as production source. They had been
# doing that for six stories: the guards asserted their property over files
# written to violate a rule, and passed only because the rule violated was not
# the rule being asserted.
#
# So the contract here is narrow and the tests are about the contract: one
# answer, the same answer the phase lock would give, available to anything that
# can run a command and read a line.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

FIX="$(make_project_fixture)"
trap 'rm -rf "$FIX"' EXIT

cls() { ( cd "$FIX" && bash scripts/classify.sh "$@" 2>&1 ); }

# ---------------------------------------------------------------------------
describe "paths as arguments"

assert_eq "a source module" "source	src/main.ts"       "$(cls src/main.ts)"
assert_eq "a test file"     "test	tests/main.test.ts" "$(cls tests/main.test.ts)"
assert_eq "a doc"           "docs	docs/notes.md"      "$(cls docs/notes.md)"

# Several at once, in the order given - a guard classifying a whole tree wants
# one process, not one per file.
assert_eq "several, in order" "source	src/main.ts
test	tests/main.test.ts" "$(cls src/main.ts tests/main.test.ts)"

# ---------------------------------------------------------------------------
describe "paths on stdin"

# The form a scanner in another language reaches for: pipe it a file list.
got="$( cd "$FIX" && printf 'src/main.ts\ndocs/notes.md\n' | bash scripts/classify.sh 2>&1 )"
assert_eq "stdin, one path per line" "source	src/main.ts
docs	docs/notes.md" "$got"

# ---------------------------------------------------------------------------
describe "--only filters to one category"

# No category column here: the output is a file list, which is what the caller
# is going to iterate. Adding a column they have to strip is how a helper gets
# reimplemented.
assert_eq "--only source" "src/main.ts" "$(cls --only source src/main.ts tests/main.test.ts docs/notes.md)"
assert_eq "--only test"   "tests/main.test.ts" "$(cls --only test src/main.ts tests/main.test.ts)"
assert_eq "--only with no match is empty, not an error" "" "$(cls --only config src/main.ts)"

# ---------------------------------------------------------------------------
describe "--list enumerates the tree the way the lock sees it"

# The whole point: a guard asking "every source file under src/" gets the
# classifier's answer, not a fourth regex. It enumerates through git - tracked
# files AND untracked ones that are not ignored - so a module written five
# minutes ago is still seen. Probes are excluded by CLASSIFICATION, never by
# tracking status: a scanner that skipped untracked files would quietly stop
# checking every new module, which is the vacuous pass this repository keeps
# warning about.
printf 'export const y = 2\n' > "$FIX/src/other.ts"
got="$(cls --list source src)"
assert_contains "an untracked new module is still source" "src/other.ts" "$got"
assert_contains "and so is the tracked one"               "src/main.ts"  "$got"
case "$got" in
  *tests/*|*docs/*) _bad "--list source excludes other categories" "leaked: $got" ;;
  *) _ok "--list source excludes other categories" ;;
esac

# INSTALLED DEPENDENCIES ARE NOT THE TREE. The enumeration is
# `git ls-files --cached --others --exclude-standard`, and that last flag is the
# only thing keeping untracked-but-ignored files out of it. Dropping it left
# every assertion in this suite green while `--list` began handing callers
# `node_modules` - which is precisely the "a guard scanning the wrong file set"
# failure classify.sh exists to prevent, arriving through the tool built to
# prevent it.
#
# ASSERTED ON `--list vendor`, and the reason is the trap. A `node_modules`
# path classifies as `vendor`, never as `source`, so `--list source` cannot
# return one whether the flag is there or not - an assertion written against
# `source` passes for a reason that has nothing to do with what it claims, and
# survives the mutation it was written to kill. Measured before being believed:
#   classify node_modules/left-pad/index.js  -> vendor
#   --list vendor, with the flag             -> nothing
#   --list vendor, without it                -> node_modules/left-pad/index.js
mkdir -p "$FIX/node_modules/left-pad"
printf 'module.exports = 1\n' > "$FIX/node_modules/left-pad/index.js"
printf 'export const z = 3\n'  > "$FIX/src/fresh.ts"
case "$(cls --list vendor)" in
  *node_modules*) _bad "--list never returns an ignored dependency tree" "node_modules came back" ;;
  *) _ok "--list never returns an ignored dependency tree" ;;
esac
got="$(cls --list source)"
# THE CONTROL, and the reason the fix cannot be "skip untracked files": a module
# written five minutes ago and not yet committed is still source, and a scanner
# that quietly stopped seeing new modules would be the same defect pointing the
# other way.
assert_contains "while an untracked, non-ignored module still is" "src/fresh.ts" "$got"
rm -rf "$FIX/node_modules" "$FIX/src/fresh.ts"

# ---------------------------------------------------------------------------
describe "a probe artifact is not a source module"

# THE case this was built for. A guard that tests a lint RULE - rather than
# today's imports - has to write a deliberately offending module into the real
# tree, because path-scoped lint overrides mean a probe linted from a temp
# directory is linted under the wrong rules. So probes live under src/, and
# every tree-scanning guard must skip them. Name them per the convention and
# both the scanner and the phase lock agree, from one rule in paths.conf.
printf 'import "../core/nope"\n' > "$FIX/src/__import_guard_probe.ts"
assert_eq "a probe classifies as test" "test	src/__import_guard_probe.ts" \
  "$(cls src/__import_guard_probe.ts)"
got="$(cls --list source src)"
case "$got" in
  *__import_guard_probe*) _bad "--list source skips probes" "the probe came back as source: $got" ;;
  *) _ok "--list source skips probes" ;;
esac
# Both directions, because an exclusion that is too broad is the second-order
# trap: a real module is still source even when its name contains the word.
assert_contains "and a real module is still listed" "src/main.ts" "$got"
assert_eq "a module merely named 'probe' is source" "source	src/heat_probe.ts" \
  "$(cls src/heat_probe.ts)"

# ---------------------------------------------------------------------------
describe "the harness's own code is tooling, not harness (HARNESS-020, AC-1)"

# scripts/** and .claude/hooks/** are the harness's production code: split out
# of `harness` into `tooling` so the lock can freeze them where it freezes
# `source`. This fixture carries the REAL scripts and hooks (make_project_fixture
# copies them), so --list answers about the files a real tree has.
assert_eq "scripts/check-boundaries.sh classifies as tooling" \
  "tooling	scripts/check-boundaries.sh" "$(cls scripts/check-boundaries.sh)"
assert_eq ".claude/hooks/phase-guard.sh classifies as tooling" \
  "tooling	.claude/hooks/phase-guard.sh" "$(cls .claude/hooks/phase-guard.sh)"
assert_eq "a new file under scripts/ classifies as tooling" \
  "tooling	scripts/new-tool.sh" "$(cls scripts/new-tool.sh)"

# --list tooling scripts returns exactly the scripts git sees under scripts/ -
# compared as a whole list, not with a floating contains, so a partial match
# (one script classified, the rest left harness) is a failure that names them.
expected_scripts="$(git -C "$FIX" ls-files --cached --others --exclude-standard -- scripts | sort)"
got="$(cls --list tooling scripts)"; rc=$?
assert_eq "--list tooling is accepted" 0 "$rc"
assert_eq "--list tooling scripts lists every script" "$expected_scripts" "$(printf '%s\n' "$got" | sort)"
# The instrument: the expected list is not empty, or the comparison above would
# pass on a tree with no scripts at all.
assert_eq "and there are scripts to list (the fixture copied them)" 1 \
  "$(awk '$0 == "scripts/check-boundaries.sh" { n++ } END { print n + 0 }' <<< "$expected_scripts")"
assert_eq "--list harness scripts lists none of them" "" "$(cls --list harness scripts)"

expected_hooks="$(git -C "$FIX" ls-files --cached --others --exclude-standard -- .claude/hooks | sort)"
assert_eq "--list tooling .claude/hooks lists every hook" "$expected_hooks" \
  "$(cls --list tooling .claude/hooks | sort)"
assert_eq "--list harness .claude/hooks lists none of them" "" "$(cls --list harness .claude/hooks)"

# ---------------------------------------------------------------------------
describe "a doc a covers line names is still docs (HARNESS-021, AC-6)"

# A `covers | unit | docs/wiki/game/tuning.md` line puts that doc into the gate
# hash. It changes nothing here: "is it gated?" is answered by gated_stdin, and
# "who may write it, in which phase?" by the category, which stays `docs`. The
# comparison is the whole output line, so a category that merely CONTAINS the
# word would not pass. Passes on arrival; earned by mutating paths.conf's
# `docs | docs/**` rule and watching it go red (see the story's ## Handoff).
mkdir -p "$FIX/docs/wiki/game"
printf '| roundSeconds | 90 |\n' > "$FIX/docs/wiki/game/tuning.md"
write_conf "$FIX" <<'CONF'
gate   | unit | required | . | true
covers | unit | docs/wiki/game/tuning.md
CONF
assert_eq "AC-6: docs/wiki/game/tuning.md classifies as docs with the covers line present" \
  "docs	docs/wiki/game/tuning.md" "$(cls docs/wiki/game/tuning.md)"
assert_contains "AC-6: and --list docs still returns it" "docs/wiki/game/tuning.md" "$(cls --list docs docs)"

# ---------------------------------------------------------------------------
describe "the category list cannot drift from paths.conf"

# The bug this closes, found by a mutation audit: classify.sh printed `manifest`
# for Cargo.toml and then refused `--only manifest` as an unknown category. The
# whitelist was a hand-copied list, and when paths.conf gained `manifest` the
# copy did not. A script that contradicts itself in two lines is worse than one
# with no validation, because the validation is what you trust.
#
# So it is derived from paths.conf now, plus the four the classifier produces
# without a rule. Deriving is the fix; a longer copy would just drift later.
assert_eq "--only manifest is accepted" "Cargo.toml" "$(cls --only manifest Cargo.toml src/main.ts)"
printf "[package]
" > "$FIX/Cargo.toml"
assert_contains "and --list manifest" "Cargo.toml" "$(cls --list manifest .)"
assert_contains "the usage lists it too" "manifest" "$(cls --only 2>&1)"

# A category invented in paths.conf is accepted without touching this script.
printf 'weird | src/weird/**\n' >> "$FIX/.claude/harness/paths.conf"
mkdir -p "$FIX/src/weird" && printf 'x\n' > "$FIX/src/weird/thing.ts"
assert_eq "a category added to paths.conf needs no code change" "weird	src/weird/thing.ts" \
  "$(cls src/weird/thing.ts)"
assert_eq "and filters by it"  "src/weird/thing.ts" "$(cls --only weird src/weird/thing.ts src/main.ts)"

# Still refuses a real typo, which is the whole point of having a list: a
# mistyped --only returns nothing, and nothing reads exactly like "this tree has
# no such files".
out="$(cls --only sources src/main.ts 2>&1)"; rc=$?
assert_eq "a typo is still refused" 2 "$rc"
assert_contains "and named" "sources" "$out"
describe "it refuses what it cannot answer"

out="$(cls --only 2>&1)"; rc=$?
assert_eq "--only with no category is a usage error" 2 "$rc"
out="$(cls --nonsense src/main.ts 2>&1)"; rc=$?
assert_eq "an unknown option is a usage error" 2 "$rc"
assert_contains "and says so" "usage" "$(printf '%s' "$out" | tr 'A-Z' 'a-z')"

# ---------------------------------------------------------------------------
describe "--gated lists what the gate tree hash covers, and only that (HARNESS-022, AC-1..AC-3)"

# A test helper (tests/helpers/GatedFs.luau) refuses a read of any file that is
# not in the gate tree hash, and it ASKS this mode rather than re-deriving
# gated_stdin. So `--gated` has to agree with gate_tree_hash by construction -
# the same `classify_stdin | gated_stdin` pipeline, fed the `--list`
# enumeration - and this block pins that agreement from both sides: what it
# prints moves the hash (AC-2's moving case reads its path OUT of the --gated
# output, so a mode printing nothing fails it), and what it does not print
# does not.
#
# Its own fixture, committed with the covers line already in project.conf
# (the oracle partition: write_conf BEFORE the commit), and with one path per
# category the hash can meet: source, a covered doc, an uncovered doc, a
# story file, a harness prompt, and an ignored build artefact.
GFIX="$(make_project_fixture)"
trap 'rm -rf "$FIX" "$GFIX"' EXIT
mkdir -p "$GFIX/docs/wiki/game" "$GFIX/docs/backlog/stories" "$GFIX/.claude/commands" "$GFIX/build"
printf '| roundSeconds | 90 |\n' > "$GFIX/docs/wiki/game/tuning.md"
printf '# architecture\n'       > "$GFIX/docs/wiki/architecture.md"
printf -- '---\nid: T-1\nphase: RED\n---\n' > "$GFIX/docs/backlog/stories/T-1.md"
printf '# x\n'                  > "$GFIX/.claude/commands/x.md"
printf 'build/\n'              >> "$GFIX/.gitignore"
printf 'out\n'                  > "$GFIX/build/out.txt"
write_conf "$GFIX" <<'CONF'
gate   | unit | required | . | true
covers | unit | docs/wiki/game/tuning.md
CONF
git -C "$GFIX" add -A >/dev/null 2>&1
git -C "$GFIX" -c user.email=t@t -c user.name=t commit -qm "gated fixture" >/dev/null 2>&1

gcls() { ( cd "$GFIX" && bash scripts/classify.sh "$@" 2>&1 ); }
# The real lib.sh, pointed at the fixture, in a subshell so that nothing it
# exports leaks into the `cls` calls above (they resolve their own root).
gth() { ( cd "$GFIX" && export CLAUDE_PROJECT_DIR="$GFIX" && . "$REPO_ROOT/.claude/hooks/lib.sh" && gate_tree_hash ); }
# Whole-line count: 1 means printed exactly once as a line of its own, 0 means
# not printed as a line. A floating `contains` would let `src/main.ts.bak` or a
# usage message that quotes the path satisfy it.
lines_eq() { printf '%s\n' "$1" | grep -cx -- "$2"; }

# --- AC-1 -------------------------------------------------------------------
out="$(gcls --gated)"; rc=$?
assert_eq "AC-1: --gated exits 0" 0 "$rc"
assert_eq "AC-1: --gated prints src/main.ts as a whole line"               1 "$(lines_eq "$out" src/main.ts)"
assert_eq "AC-1: --gated prints the covered docs/wiki/game/tuning.md"      1 "$(lines_eq "$out" docs/wiki/game/tuning.md)"
assert_eq "AC-1: --gated does not print the uncovered docs/wiki/architecture.md" 0 "$(lines_eq "$out" docs/wiki/architecture.md)"
assert_eq "AC-1: --gated does not print the story file docs/backlog/stories/T-1.md" 0 "$(lines_eq "$out" docs/backlog/stories/T-1.md)"
assert_eq "AC-1: --gated does not print the harness prompt .claude/commands/x.md" 0 "$(lines_eq "$out" .claude/commands/x.md)"
assert_eq "AC-1: --gated does not print the ignored build/out.txt"         0 "$(lines_eq "$out" build/out.txt)"
# No category column: the output is a file list, which is what GatedFs splits
# on newlines and compares whole.
assert_eq "AC-1: --gated prints no category column" 0 "$(printf '%s\n' "$out" | grep -c "$(printf '\t')")"

# Control: the same tree without the covers line. tuning.md drops out and
# src/main.ts stays, so the covers line is the cause and the mode is not
# "everything under docs/" or "nothing".
write_conf "$GFIX" <<'CONF'
gate   | unit | required | . | true
CONF
out="$(gcls --gated)"
assert_eq "AC-1 control: without the covers line, tuning.md is not printed" 0 "$(lines_eq "$out" docs/wiki/game/tuning.md)"
assert_eq "AC-1 control: and src/main.ts still is"                          1 "$(lines_eq "$out" src/main.ts)"
write_conf "$GFIX" <<'CONF'
gate   | unit | required | . | true
covers | unit | docs/wiki/game/tuning.md
CONF

# --- AC-2 -------------------------------------------------------------------
# Paired through --gated's OWN OUTPUT: the path edited in the moving case is
# the docs path --gated printed, not a name this test chose. A --gated that
# lists something the hash ignores fails the moving case; one that omits
# something the hash counts fails the static case (asserted not printed in
# AC-1 above, then shown not to move). Each edit has its own before and after.
out="$(gcls --gated)"
moving="$(printf '%s\n' "$out" | grep '^docs/' | head -n 1)"
assert_eq "AC-2: --gated printed exactly one docs path, tuning.md, to edit" "docs/wiki/game/tuning.md" "$moving"
h0="$(gth)"
case "$h0" in unavailable|'') _bad "AC-2: gate_tree_hash is available on the fixture" "got: '$h0'" ;; *) _ok "AC-2: gate_tree_hash is available on the fixture" ;; esac
if [ -z "$moving" ]; then
  _bad "AC-2: editing the doc --gated printed moves the hash" "--gated printed no docs path, so there was nothing to edit; its output was: $out"
else
  printf '| roundSeconds | 91 |\n' > "$GFIX/$moving"
  h1="$(gth)"
  if [ "$h1" = "$h0" ]; then _bad "AC-2: editing the doc --gated printed moves the hash" "unchanged: $h0"; else _ok "AC-2: editing the doc --gated printed moves the hash"; fi
fi
h2="$(gth)"
printf '# architecture, reworded\n' > "$GFIX/docs/wiki/architecture.md"
assert_eq "AC-2: editing the doc --gated did not print leaves the hash unchanged" "$h2" "$(gth)"

# --- AC-3 -------------------------------------------------------------------
out="$(gcls --gated docs)"
assert_eq "AC-3: --gated docs prints tuning.md"          1 "$(lines_eq "$out" docs/wiki/game/tuning.md)"
assert_eq "AC-3: --gated docs does not print src/main.ts" 0 "$(lines_eq "$out" src/main.ts)"
out="$(gcls --gated docs/wiki/game/nope.md)"; rc=$?
assert_eq "AC-3: --gated on a path that does not exist exits 0" 0 "$rc"
assert_eq "AC-3: and prints nothing" "" "$out"
# A pathspec narrows the QUESTION, not the answer: naming an ignored file
# does not make it gated.
out="$(gcls --gated build/out.txt)"; rc=$?
assert_eq "AC-3: --gated build/out.txt (ignored) exits 0" 0 "$rc"
assert_eq "AC-3: and prints nothing for the ignored file" "" "$out"
# An untracked, non-ignored file written after the commit - the path GatedFs
# takes on a miss, for a probe written mid-run.
printf 'export const late = 1\n' > "$GFIX/src/late.ts"
out="$(gcls --gated src/late.ts)"
assert_eq "AC-3: an untracked src/late.ts created after the commit is printed by --gated src/late.ts" 1 "$(lines_eq "$out" src/late.ts)"

summary "classify"
