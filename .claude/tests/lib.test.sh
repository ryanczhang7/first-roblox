#!/usr/bin/env bash
# Unit tests for .claude/hooks/lib.sh - the path classifier and the shell-quote
# masker the phase guard is built on.
#
# phase-guard.test.sh drives the hook end to end; this covers the pieces
# directly, so that a failure says which one broke.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

FIX="$(make_fixture)"
trap 'rm -rf "$FIX"' EXIT

export CLAUDE_PROJECT_DIR="$FIX"
. "$REPO_ROOT/.claude/hooks/lib.sh"

# ---------------------------------------------------------------------------
describe "classify: paths.conf rules"

# HARNESS-020: scripts/** and .claude/hooks/** are `tooling` - the harness's
# own production code, frozen wherever `source` is - and everything else under
# .claude/ and the harness's root files stays `harness`, writable in every
# phase (AC-1, AC-4). A new file under scripts/ is tooling too: the rule is the
# tree, not today's inventory.
for case in \
  "src/main.ts=source" \
  "src/deep/nested/thing.ts=source" \
  "tests/main.test.ts=test" \
  "src/main.test.ts=test" \
  "docs/backlog/stories/T-1.md=docs" \
  "README.md=docs" \
  ".claude/hooks/lib.sh=tooling" \
  ".claude/hooks/phase-guard.sh=tooling" \
  ".claude/tests/lib.test.sh=harness" \
  "scripts/gates.sh=tooling" \
  "scripts/check-boundaries.sh=tooling" \
  "scripts/new-tool.sh=tooling" \
  ".claude/tests/x.test.sh=harness" \
  ".claude/tests/_lib.sh=harness" \
  ".claude/commands/advance-story.md=harness" \
  ".claude/harness/project.conf=harness" \
  ".claude/harness/paths.conf=harness" \
  ".claude/settings.json=harness" \
  ".github/workflows/gates.yml=harness" \
  "CLAUDE.md=harness" \
  ".gitignore=harness" \
  "src/ui/__import_guard_probe.ts=test" \
  "src/core/__probe_offending_import.ts=test" \
  "src/__probe_a.py=test" \
  "src/ui/heat_probe.ts=source" \
  "src/core/probe.ts=source" \
  "LICENSE=docs" \
  "LICENSE.md=docs" \
  "COPYING=docs" \
  "NOTICE=docs" \
  "AUTHORS=docs" \
  "CONTRIBUTORS=docs" \
  "CHANGELOG.md=docs" \
  "SECURITY.md=docs" \
  ".gitattributes=harness" \
  ".editorconfig=harness" \
  ".mailmap=harness" \
  "CODEOWNERS=harness" \
  "package.json=manifest" \
  "pyproject.toml=manifest" \
  "Cargo.toml=manifest" \
  "Cargo.lock=manifest" \
  "pnpm-lock.yaml=manifest" \
  "uv.lock=manifest" \
  "go.mod=config" \
  "requirements.txt=config" \
  "tsconfig.json=config" \
  "vite.config.ts=config" \
  "vitest.config.ts=test" \
  "node_modules/left-pad/index.js=vendor" \
  "node_modules=vendor" \
  "dist/bundle.js=vendor" \
  ; do
  assert_eq "classify ${case%%=*}" "${case#*=}" "$(classify "${case%%=*}")"
done

assert_eq "classify of nothing is outside" "outside" "$(classify "")"

# ---------------------------------------------------------------------------
describe "classify: git decides what is generated"

# In the fixture's .gitignore, matched by no paths.conf rule.
assert_eq "an ignored directory"        "ignored" "$(classify ".vitest")"
assert_eq "a file inside one"           "ignored" "$(classify ".vitest/screenshot.png")"
assert_eq "an ignored report directory" "ignored" "$(classify "playwright-report")"

# Tracked, so authored, whatever any rule says.
assert_eq "a tracked source file" "source" "$(classify "src/main.ts")"

# Not ignored and not matched: the conservative default.
assert_eq "an unknown new path" "source" "$(classify "src/brand-new.ts")"

# ---------------------------------------------------------------------------
describe "to_rel"

assert_eq "a relative path"        "src/main.ts" "$(to_rel "src/main.ts")"
assert_eq "a dot-relative path"    "src/main.ts" "$(to_rel "./src/main.ts")"
assert_eq "an absolute path"       "src/main.ts" "$(to_rel "$FIX/src/main.ts")"
assert_eq "a backslash path"       "src/main.ts" "$(to_rel "$(printf '%s' "$FIX" | tr '/' '\134')\\src\\main.ts")"
assert_eq "somewhere else on disk" ""            "$(to_rel "/somewhere/else/main.ts")"

# ---------------------------------------------------------------------------
describe "mask_shell_quotes: operators inside quotes stop being operators"

mask() { printf '%s' "$1" | mask_shell_quotes; }
roundtrip() { printf '%s' "$1" | mask_shell_quotes | unmask_shell_quotes; }

# What the masker is for: no operator survives inside a quoted span.
has_operator() { grep -qE '[|&;<>]' <<< "$1"; }

for cmd in \
  "sed -i 's|a|b|' f.txt" \
  "awk '/A -> B/' f.txt" \
  "grep -oE 'x>y' f.txt" \
  'git commit -m "fix: a > b"' \
  'echo "a && b; c"' \
  'git commit -m "$(printf "%s\n%s" "GATES -> REVIEW" "set the phase first")"' \
  ; do
  masked="$(mask "$cmd")"
  # Everything after the first quote is data; only the command word and the
  # options before it may still hold punctuation, and they hold none here.
  if has_operator "${masked#*[\'\"]}"; then
    _bad "masks operators in: $cmd" "still operator-bearing: $masked"
  else
    _ok "masks operators in: $cmd"
  fi
  assert_eq "round trip: $cmd" "$cmd" "$(roundtrip "$cmd")"
done

# SEAT-002. A paren inside a quoted span is data, like every other operator
# here - and it was the one the masker left alone. `s/\(a\)/b/` is what a real
# sed script looks like, and every extractor in phase-guard.sh terminates its
# match at `(`, so the group truncated the command mid-word and the fragment
# left behind was taken for the write target. Masking it is not a special case
# for sed: a subshell paren is syntax, a quoted one is a character.
has_paren() { grep -qF '(' <<< "$1"; }
for cmd in \
  "sed -i 's/\(a\)/b/' f.txt" \
  "sed -i 's/(43)/(47)/' f.txt" \
  'grep -oE "(a|b)c" f.txt' \
  "awk 'BEGIN { print (1) }' f.txt" \
  ; do
  masked="$(mask "$cmd")"
  if has_paren "${masked#*[\'\"]}"; then
    _bad "masks parens in: $cmd" "still paren-bearing: $masked"
  else
    _ok "masks parens in: $cmd"
  fi
  assert_eq "round trip: $cmd" "$cmd" "$(roundtrip "$cmd")"
done

# And the control, because masking every paren everywhere would delete the
# terminator that stops `(cd src && echo x > a.ts)` yielding a target of
# `a.ts)`. An UNQUOTED paren is still shell syntax.
assert_contains "an unquoted subshell paren survives masking" "(" "$(mask '(cd src && echo x > a.ts)')"
assert_contains "so does its closing paren"                   ")" "$(mask '(cd src && echo x > a.ts)')"
assert_contains "and an unquoted command substitution keeps its paren" "(" "$(mask 'printf x > $(mktemp)')"

describe "mask_shell_quotes: structure outside quotes is preserved"

for cmd in \
  'echo hi > out.txt' \
  'cat a.txt | tee b.txt' \
  'rm -rf dist && mkdir dist' \
  'sed -i "s/a/b/" f.txt' \
  ; do
  assert_eq "round trip: $cmd" "$cmd" "$(roundtrip "$cmd")"
done

assert_contains "an unquoted redirect survives masking" ">" "$(mask 'echo hi > out.txt')"
assert_contains "an unquoted pipe survives masking"     "|" "$(mask 'cat a | tee b')"

describe "mask_shell_quotes: heredocs and escapes"

hd="$(mask "$(printf 'cat > notes.md <<%sEOF%s\nrun: cat > src/main.ts\nEOF\n' "'" "'")")"
assert_contains "the real redirect survives" "> notes.md" "$hd"
if grep -q '> src/main.ts' <<< "$hd"; then
  _bad "a heredoc body is masked" "the body's redirect survived: $hd"
else
  _ok "a heredoc body is masked"
fi

assert_eq "an escaped operator is masked" "0" \
  "$(mask 'echo a \> b' | grep -cE '>')"

describe "mask_shell_quotes: a backslash inside double quotes is usually a backslash"

# Bash escapes only five things inside double quotes: $ ` " \ and newline.
# Every other backslash is literal - which is every backslash in a Windows
# path. A masker that eats them turns the scratchpad this harness tells agents
# to use into `C:UsersryancAppDataLocalTempclaude`, which is not outside the
# repository as far as to_rel can tell, so it falls through to `source` and the
# write is denied. Observed on a Windows machine in RED.
for cmd in \
  'echo x > "C:\Users\ryanc\AppData\Local\Temp\claude\n.txt"' \
  'cd "C:\Users\ryanc\AppData\Local\Temp\claude" && rm -rf x' \
  'printf "%s\n" "a\tb"' \
  ; do
  assert_eq "round trip keeps literal backslashes: $cmd" "$cmd" "$(roundtrip "$cmd")"
done
# The ones that ARE escapes still are: the escaped quote does not end the
# string, so the arrow inside it is masked and only the real redirect is left.
assert_eq "an escaped quote does not end the string" "1" \
  "$(mask 'echo "a \" > b" > docs/notes.md' | tr -cd '>' | wc -c | tr -d ' ')"

describe "mask_shell_quotes: a comment is data to the end of the line"

# `# it's fine` - the apostrophe opens a single-quoted span that never closes,
# and everything after it, on every following line, is masked. A real redirect
# on the next line vanished. Observed by probe, not in the field, but the
# shape - a chatty comment, then the write - is an everyday one.
two="$(printf 'echo hi # it%ss fine\necho x > src/main.ts' "'")"
assert_contains "a redirect after a commented apostrophe survives" "> src/main.ts" "$(mask "$two")"
assert_eq "a # inside a word is not a comment" "echo a#b > out.txt" "$(mask 'echo a#b > out.txt' | unmask_shell_quotes)"
assert_contains "a # inside a word still leaves the redirect" ">" "$(mask 'echo a#b > out.txt')"

# ---------------------------------------------------------------------------
describe "json_escape: a backslash is escaped, not dropped"

# The deny reason is emitted as JSON. A backslash in it - a Windows path, a
# regex the guard quotes back - has to arrive doubled or the hook's output is
# not JSON at all.
assert_eq "a backslash"      'a\\b'     "$(json_escape 'a\b')"
assert_eq "a quote"          'a\"b'     "$(json_escape 'a"b')"
assert_eq "a newline"        'a\nb'     "$(json_escape "$(printf 'a\nb')")"
assert_eq "a tab"            'a\tb'     "$(json_escape "$(printf 'a\tb')")"
assert_eq "a carriage return is dropped" 'ab' "$(json_escape "$(printf 'a\rb')")"

# ---------------------------------------------------------------------------
describe "gate_tree_hash: agrees with the committed tree whatever autocrlf says"

# The hash is recorded from the working tree and recomputed by CI from the PR
# head commit. Adding into an EMPTY index treats every file as new, so git
# applies CRLF normalisation the real commit never had - and the two hashes
# disagree on any CRLF file committed before .gitattributes pinned LF. Then
# re-running the gates cannot fix it, because the working tree is not what is
# wrong.
HARNESS_ROOT="$FIX"
git -C "$FIX" config core.autocrlf false
printf 'export const crlf = 1\r\n' > "$FIX/src/crlf.ts"
git -C "$FIX" add -A >/dev/null 2>&1
git -C "$FIX" -c user.email=t@t -c user.name=t commit -qm "crlf file" >/dev/null 2>&1
git -C "$FIX" config core.autocrlf true
assert_eq "working tree hash equals HEAD hash under autocrlf=true" \
  "$(gate_tree_hash_of HEAD)" "$(gate_tree_hash)"
git -C "$FIX" config core.autocrlf false

# ---------------------------------------------------------------------------
describe "portability: the harness runs on bash 3.2 and BSD tools"

# gates.sh names bash 3.2 as a target and macOS ships 3.2.57. `${var,,}`
# is a bash 4 feature; on 3.2 it is a "bad substitution" that kills to_rel,
# and a to_rel that dies makes check_path return "allow" - the lock silently
# off on every stock Mac. `sed -i` with no suffix is GNU-only; BSD sed reads
# the next argument as the backup suffix. Both are caught here by reading the
# code, because nothing else in this suite can run the other platform.
shipped="$(ls "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/.claude/hooks/*.sh)"
hits="$(grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)\}' $shipped || true)"
assert_eq "no \${var,,} or \${var^^} in shipped scripts" "" "$hits"
hits="$(grep -nE '(^|[[:space:]|;&(])sed[[:space:]]+(-[A-Za-z]*\s+)*-i([[:space:]]|$)' $shipped || true)"
assert_eq "no GNU-only sed -i in shipped scripts" "" "$hits"

# A fallback that cannot fire is not a fallback. Every suite opens with
# `mktemp -d 2>/dev/null || mktemp -d -t harness`, and GNU's -t wants X's in the
# template: `mktemp -d -t harness` is "too few X's in template". So on the only
# platform where the first half could fail, the second half fails too. Latent,
# because plain `mktemp -d` is universal - and exactly the kind of guard that
# reads as handled in review. Found by a consuming project pre-checking this
# repository's suites for Linux hazards before running them there.
#
# The failure MESSAGE carries two facts, and both are load-bearing for a reader
# who is not in this conversation. This check scans `.claude/tests/*.sh`, which
# in a vendored copy includes the PROJECT'S OWN suites - so an upstream
# portability rule can fail on a file the project wrote. That is deliberate: the
# hazard is identical wherever the idiom appears, and a rule that stops applying
# the moment it is vendored is one more check nothing has to listen to. But an
# agent with a fresh context sees an upstream rule failing on its own file and
# reads "the vendored suite is stale", which makes skipping it feel like the
# careful move. So the message says that project files are in scope on purpose,
# and gives the exact replacement rather than making the reader derive it.
hits="$(grep -rnE 'mktemp -d[^|)]*-t [A-Za-z0-9_.-]+' "$REPO_ROOT"/.claude/tests/*.sh "$REPO_ROOT"/scripts/*.sh 2>/dev/null \
  | grep -vE ':[0-9]+:[[:space:]]*#' | grep -v 'XXX' || true)"
if [ -z "$hits" ]; then
  _ok "no mktemp -t template without X's"
else
  # The example below is deliberately NOT written as a contiguous
  # 'mktemp' + '-d' + '-t name', because this message is itself inside a file
  # this check scans - writing the broken form here makes the message a hit and
  # the check report itself. It did, on the first run.
  _bad "no mktemp -t template without X's" "GNU's -t needs X's in the template: a -t given a bare name fails with
\"too few X's in template\", so the fallback cannot run on the one platform
where the plain create-a-temp-dir call before it could fail.

Fix each site by adding them:   -t name   ->   -t name.XXXXXX

PROJECT-OWNED SUITES ARE IN SCOPE ON PURPOSE. If one of the files below is
yours rather than the harness's, that is not a stale vendored suite and not a
reason to skip this - the idiom is broken wherever it appears, and this rule
reaching your files is the point of it. Fix it in place; it is one line.

$hits"
fi

# $TMPDIR is unset in some of the shells this harness runs in, and the one place
# that mattered - a mutation backup - lost its backup to exactly that, leaving
# the restore to depend on the sed expression happening to be an exact inverse.
# Nothing shipped may write to a temporary directory it did not name itself.
# Comments are allowed to mention it; code is not.
hits="$(grep -nE '\$\{?TMPDIR|\bmktemp\b' $shipped | grep -vE ':[[:space:]]*#' || true)"
assert_eq "no shipped script depends on \$TMPDIR or mktemp" "" "$hits"

# ---------------------------------------------------------------------------
describe "glob_matches: the paths.conf glob dialect, reusable"

# `covers` lines in project.conf use the same globs as paths.conf, through the
# same function, so a glob that classifies a path also covers it.
for pair in \
  'src/**=src/render/mesh.ts' \
  'src/**=src/a.ts' \
  'src/render/**=src/render/deep/x.ts' \
  '**/*.test.*=src/a.test.ts' \
  'src/*.ts=src/a.ts' \
  'SRC/**=src/a.ts' \
  ; do
  g="${pair%%=*}"; p="${pair#*=}"
  if glob_matches "$g" "$p"; then _ok "matches: $g ~ $p"; else _bad "matches: $g ~ $p" "no match"; fi
done
for pair in \
  'src/render/**=src/core/a.ts' \
  'src/*.ts=src/deep/a.ts' \
  'src/**=lib/src/a.ts' \
  'src/a.ts=src/a.tsx' \
  ; do
  g="${pair%%=*}"; p="${pair#*=}"
  if glob_matches "$g" "$p"; then _bad "does not match: $g ~ $p" "matched"; else _ok "does not match: $g ~ $p"; fi
done

# ---------------------------------------------------------------------------
describe "gate_tree_hash: covers what the gates judge, and only that"

# The hash is the identity of "the code the gates ran against". A change to a
# file no gate reads must not move it, or every prompt edit after the last run
# forces a re-run before the PR is acceptable - and it does have to move on a
# change to anything a gate does read, or the record proves nothing.
HARNESS_ROOT="$FIX"
mkdir -p "$FIX/.claude/commands" "$FIX/.claude/hooks"
printf '# advance\n' > "$FIX/.claude/commands/advance-story.md"
printf 'x() { :; }\n' > "$FIX/.claude/hooks/lib.sh"
h0="$(gate_tree_hash)"
printf '# advance, reworded\n' > "$FIX/.claude/commands/advance-story.md"
assert_eq "a command prompt does not move the hash" "$h0" "$(gate_tree_hash)"
printf '# a wiki page\n' > "$FIX/docs/notes.md"
assert_eq "a docs file does not move the hash"      "$h0" "$(gate_tree_hash)"
printf 'y() { :; }\n' > "$FIX/.claude/hooks/lib.sh"
h1="$(gate_tree_hash)"
if [ "$h1" = "$h0" ]; then _bad "a hook moves the hash" "unchanged: $h0"; else _ok "a hook moves the hash"; fi
# HARNESS-020 (AC-6). scripts/** and .claude/hooks/** are `tooling` now, and
# gated_stdin keeps an explicit list of categories: a split that forgot to add
# `tooling` to it drops both trees out of "the code the gates ran against",
# and a gate record then survives any edit to the harness's own code. Measured
# on the real tree at PLANNED: gate_tree_hash_of 01e502b is e852f851... with
# the split and 81917885... with the split but without `tooling` in
# gated_stdin. The hook case above and this one are the two that tell those
# apart - on a tree without the split they pass either way, which is why the
# story's DV-2 breaks gated_stdin against the shipped config and watches both.
mkdir -p "$FIX/scripts"
printf '#!/usr/bin/env bash\necho a\n' > "$FIX/scripts/gates.sh"
h1b="$(gate_tree_hash)"
if [ "$h1b" = "$h1" ]; then _bad "adding a script moves the hash" "unchanged: $h1"; else _ok "adding a script moves the hash"; fi
printf '#!/usr/bin/env bash\necho b\n' > "$FIX/scripts/gates.sh"
h1c="$(gate_tree_hash)"
if [ "$h1c" = "$h1b" ]; then _bad "a script moves the hash" "unchanged: $h1b"; else _ok "a script moves the hash"; fi
h1="$h1c"
printf 'export const x = 2\n' > "$FIX/src/main.ts"
h2="$(gate_tree_hash)"
if [ "$h2" = "$h1" ]; then _bad "source moves the hash" "unchanged: $h1"; else _ok "source moves the hash"; fi

# ---------------------------------------------------------------------------
describe "gate_tree_hash: a covers line brings the doc a gate reads into the hash (HARNESS-021)"

# Two docs under docs/wiki are read by `lune run test` at test time, so editing
# either after a recorded gate run changes what the unit gate would report
# while the recorded stamp still matches. The fix is option B: a
# `covers | <gate> | <glob>` line in project.conf that matches a `docs` path
# brings that path into the hash. Classification does not change.
#
# Every "does not move" case below is paired with a "does move" case in the
# SAME fixture state, so an implementation that keeps nothing cannot pass the
# block: the pairs that fail in RED are the covers-line tuning.md edits (AC-1)
# and the docs/** architecture.md edit (AC-3). Each edit gets its own before
# and after hash and its own assertion; no loop hides which path moved.
#
# The two docs are named by AC-7 and the story's measurement, not chosen here:
# tuning.md is the one the gate reads; architecture.md is the control, a doc
# that is only MENTIONED in test comments and never read.
mkdir -p "$FIX/docs/wiki/game"
TUNE_A='| roundSeconds | 90 |'
TUNE_B='| roundSeconds | 91 |'
TUNE_C='| roundSeconds | 92 |'
TUNE_D='| roundSeconds | 93 |'
printf '%s\n' "$TUNE_A"     > "$FIX/docs/wiki/game/tuning.md"
printf '# architecture\n'   > "$FIX/docs/wiki/architecture.md"

# --- AC-4, no project.conf: the state every hash case above ran in ----------
# "Equals the hash of the same tree with no covers arm" is expressed as the
# observable it implies: no doc's content is an input to the hash, so a doc
# edit leaves it where it was, while a source edit in the same state moves it.
# (A literal equality against a hash computed "without the covers arm" would
# need the test to carry its own copy of gated_stdin's first arm, which is the
# third predicate the lib.sh comment refuses to have.)
h3="$(gate_tree_hash)"
printf '%s\n' "$TUNE_B" > "$FIX/docs/wiki/game/tuning.md"
assert_eq "AC-4: with no project.conf, a doc a gate could read does not move the hash" "$h3" "$(gate_tree_hash)"
printf 'export const x = 3\n' > "$FIX/src/main.ts"
h4="$(gate_tree_hash)"
if [ "$h4" = "$h3" ]; then _bad "AC-4 pair: with no project.conf, source still moves the hash" "unchanged: $h3"; else _ok "AC-4 pair: with no project.conf, source still moves the hash"; fi

# --- AC-4, a project.conf whose only covers line is src/** -------------------
# project.conf is harness and not .md, so it is hashed itself: the baseline is
# taken AFTER the write.
write_conf "$FIX" <<'CONF'
gate   | unit | required | . | true
covers | unit | src/**
CONF
h5="$(gate_tree_hash)"
printf '%s\n' "$TUNE_A" > "$FIX/docs/wiki/game/tuning.md"
assert_eq "AC-4: covers | unit | src/** keeps no doc: tuning.md does not move the hash" "$h5" "$(gate_tree_hash)"
printf '# a wiki page, reworded\n' > "$FIX/docs/notes.md"
assert_eq "AC-4: covers | unit | src/** keeps no doc: docs/notes.md does not move the hash" "$h5" "$(gate_tree_hash)"
printf '# architecture, reworded\n' > "$FIX/docs/wiki/architecture.md"
assert_eq "AC-4: covers | unit | src/** keeps no doc: architecture.md does not move the hash" "$h5" "$(gate_tree_hash)"
printf 'export const x = 4\n' > "$FIX/src/main.ts"
h6="$(gate_tree_hash)"
if [ "$h6" = "$h5" ]; then _bad "AC-4 pair: under covers | unit | src/**, source still moves the hash" "unchanged: $h5"; else _ok "AC-4 pair: under covers | unit | src/**, source still moves the hash"; fi

# --- AC-1 control A: the SAME edit, without the covers line ------------------
# The doc goes from TUNE_A to TUNE_B here and again below; only the conf
# differs. That is what shows the covers line is the cause.
write_conf "$FIX" <<'CONF'
gate   | unit | required | . | true
CONF
printf '%s\n' "$TUNE_A" > "$FIX/docs/wiki/game/tuning.md"
h7="$(gate_tree_hash)"
printf '%s\n' "$TUNE_B" > "$FIX/docs/wiki/game/tuning.md"
assert_eq "AC-1 control: the same tuning.md edit without the covers line does not move the hash" "$h7" "$(gate_tree_hash)"

# --- AC-1: the covers line for tuning.md ------------------------------------
write_conf "$FIX" <<'CONF'
gate   | unit | required | . | true
covers | unit | docs/wiki/game/tuning.md
CONF
printf '%s\n' "$TUNE_A" > "$FIX/docs/wiki/game/tuning.md"
h8="$(gate_tree_hash)"
printf '%s\n' "$TUNE_B" > "$FIX/docs/wiki/game/tuning.md"
h9="$(gate_tree_hash)"
if [ "$h9" = "$h8" ]; then _bad "AC-1: with covers | unit | docs/wiki/game/tuning.md, editing tuning.md moves the hash" "unchanged: $h8"; else _ok "AC-1: with covers | unit | docs/wiki/game/tuning.md, editing tuning.md moves the hash"; fi
# Control B: the covers line names one doc, not "all docs".
printf '# architecture, reworded again\n' > "$FIX/docs/wiki/architecture.md"
assert_eq "AC-1 control: with the covers line, editing architecture.md (unread) does not move the hash" "$h9" "$(gate_tree_hash)"
printf '# a wiki page, reworded again\n' > "$FIX/docs/notes.md"
assert_eq "AC-1 control: with the covers line, editing docs/notes.md does not move the hash" "$h9" "$(gate_tree_hash)"
# And the pair for those two controls, in the same conf state: the named doc
# still moves it after the unread ones did not.
printf '%s\n' "$TUNE_C" > "$FIX/docs/wiki/game/tuning.md"
h10="$(gate_tree_hash)"
if [ "$h10" = "$h9" ]; then _bad "AC-1 pair: after the unread-doc edits, a second tuning.md edit still moves the hash" "unchanged: $h9"; else _ok "AC-1 pair: after the unread-doc edits, a second tuning.md edit still moves the hash"; fi
# The hash is a function of content, not of mtime: putting the content back
# puts the hash back. This is what makes a record RE-matchable after a revert,
# and it is the difference between hashing the blob and hashing the write.
printf '%s\n' "$TUNE_B" > "$FIX/docs/wiki/game/tuning.md"
assert_eq "AC-1: restoring tuning.md's content restores the hash" "$h9" "$(gate_tree_hash)"

# --- AC-3: the covers arm admits docs, and only the docs that can be hashed --
# A broad glob. The story file records the hash and cannot be an input to it,
# and harness prompts are not reopened through `covers`. The control is the
# same glob matching a doc that CAN be hashed.
write_conf "$FIX" <<'CONF'
gate   | unit | required | . | true
covers | unit | docs/**
covers | unit | .claude/commands/**
CONF
printf -- '---\nid: T-1\nphase: GREEN\n---\n\n## Gate results\n\n' > "$FIX/docs/backlog/stories/T-1.md"
h11="$(gate_tree_hash)"
printf -- '---\nid: T-1\nphase: GATES\n---\n\n## Gate results\n\n  tree: %s\n' "$h11" > "$FIX/docs/backlog/stories/T-1.md"
assert_eq "AC-3: under covers | unit | docs/**, the story file docs/backlog/stories/T-1.md does not move the hash" "$h11" "$(gate_tree_hash)"
printf '# advance, reworded under a covers glob\n' > "$FIX/.claude/commands/advance-story.md"
assert_eq "AC-3: under covers | unit | .claude/commands/**, a command prompt does not move the hash" "$h11" "$(gate_tree_hash)"
printf '# architecture, under docs/**\n' > "$FIX/docs/wiki/architecture.md"
h12="$(gate_tree_hash)"
if [ "$h12" = "$h11" ]; then _bad "AC-3 control: under covers | unit | docs/**, editing docs/wiki/architecture.md moves the hash" "unchanged: $h11"; else _ok "AC-3 control: under covers | unit | docs/**, editing docs/wiki/architecture.md moves the hash"; fi
printf '%s\n' "$TUNE_D" > "$FIX/docs/wiki/game/tuning.md"
h13="$(gate_tree_hash)"
if [ "$h13" = "$h12" ]; then _bad "AC-3 control: under covers | unit | docs/**, editing tuning.md moves the hash" "unchanged: $h12"; else _ok "AC-3 control: under covers | unit | docs/**, editing tuning.md moves the hash"; fi
# The exclusion is by the docs/backlog/ prefix, not by the file being named
# T-1.md: an epic under docs/backlog/epics/ stays out too.
mkdir -p "$FIX/docs/backlog/epics"
printf '# epic\n' > "$FIX/docs/backlog/epics/E-1.md"
h14="$(gate_tree_hash)"
printf '# epic, reworded\n' > "$FIX/docs/backlog/epics/E-1.md"
assert_eq "AC-3: under covers | unit | docs/**, an epic under docs/backlog/ does not move the hash either" "$h14" "$(gate_tree_hash)"

# ---------------------------------------------------------------------------
describe "path_is_implausible: a failed parse is inconclusive, not a violation"

# The tokens on the left were all reported as the `path:` of a real denial, on
# commands that wrote nothing. None of them is a path; the guard declines to
# judge them rather than treating its own parse failure as evidence.
for t in '=' '[^' '--' '>' '' '`mktemp`' '$TMPDIR/x' 'a(b)'; do
  if path_is_implausible "$t"; then _ok "implausible: '$t'"
  else _bad "implausible: '$t'" "the guard believed this was a path"; fi
done

# The other half of the rule, and the one that keeps it honest: everything a
# real project actually names must still be judged. A bracketed route segment
# is a real path in more than one framework.
for t in 'src/main.ts' 'src/app/[id]/page.tsx' 'src/my file.ts' '.gitignore' \
         'a' 'docs/wiki/architecture.md' 'src/a-b_c.2.ts'; do
  if path_is_implausible "$t"; then _bad "plausible: '$t'" "the guard refused to judge a real path"
  else _ok "plausible: '$t'"; fi
done


# ---------------------------------------------------------------------------
describe "shell_assignments: what the command text says a variable holds"

m() { printf '%s' "$1" | mask_shell_quotes; }

assert_eq "a bare assignment" "F=src/main.ts" \
  "$(shell_assignments "$(m 'F=src/main.ts; rm "$F"')")"
assert_eq "a quoted value keeps its path, loses its quotes" "F=src/main.ts" \
  "$(shell_assignments "$(m 'F="src/main.ts"; rm "$F"')")"

# Longest name first, so that a rule for $F cannot eat $FILE.
assert_eq "longest name first" "FILE=src/a.ts
F=docs" \
  "$(shell_assignments "$(m 'F=docs; FILE=src/a.ts; rm "$FILE"')")"

# Inside quotes there is no assignment, only text. Masking is what makes this
# true without a second parser: the space before it is a control character by
# now, so the pattern cannot match.
assert_eq "an equals sign inside a commit message" "" \
  "$(shell_assignments "$(m 'git commit -m "note: A=b was wrong"')")"
assert_eq "an equals sign inside a quoted printf" "" \
  "$(shell_assignments "$(m "printf '%s' 'X=y'")")"

# ---------------------------------------------------------------------------
describe "resolve_vars: resolved, or left with its \$ for the decline to catch"

A="$(shell_assignments "$(m 'F=src/main.ts; D=src')")"
assert_eq "a plain expansion"  "src/main.ts" "$(resolve_vars '$F' "$A")"
assert_eq "a braced expansion" "src/main.ts" "$(resolve_vars '${F}' "$A")"
assert_eq "a variable plus a suffix" "src/main.ts" "$(resolve_vars '$D/main.ts' "$A")"
assert_eq "text with no variable is returned unchanged" "src/main.ts" \
  "$(resolve_vars 'src/main.ts' "$A")"

# The honest limit: the guard reads one command string, not the shell's
# environment. What it cannot resolve keeps its `$`, and path_is_implausible
# declines on it rather than pretending to have checked it.
assert_eq "an unknown name survives untouched" '$ELSEWHERE' \
  "$(resolve_vars '$ELSEWHERE' "$A")"
if path_is_implausible "$(resolve_vars '$ELSEWHERE' "$A")"; then
  _ok "and is then declined"
else _bad "and is then declined" "the guard believed an unresolved variable was a path"; fi

# ---------------------------------------------------------------------------
describe "mutate_targets: the one file a mutation is allowed to touch"

assert_eq "the FILE argument" "src/main.ts" \
  "$(mutate_targets "$(m "bash scripts/mutate.sh src/main.ts 's/a/b/' -- true")")"
assert_eq "quoted, with a | in the expression" "src/main.ts" \
  "$(mutate_targets "$(m "bash scripts/mutate.sh \"src/main.ts\" 's|a|b|' -- true")")"
assert_eq "nothing when mutate.sh is not involved" "" \
  "$(mutate_targets "$(m "sed -i 's/a/b/' src/main.ts")")"

# A file that merely happens to be called mutate.sh is not this script.
assert_eq "only scripts/mutate.sh" "" \
  "$(mutate_targets "$(m "bash tools/mutate.sh src/main.ts 's/a/b/' -- true")")"

summary "lib"
