#!/usr/bin/env bash
# HARNESS-007 - the roblox-luau PROFILE must teach the counter HARNESS-006 built.
#
# WHY THIS FILE, AND WHY NOT ONE OF THE TWO OBVIOUS HOMES:
#   * .claude/tests/profiles.test.sh is UPSTREAM's. scripts/refresh-harness.sh
#     replaces .claude/tests wholesale for every file upstream ships, so a check
#     added there is deleted by the next refresh and AC-7 becomes decoration.
#     Verified: `ls ../agentic-dev-harness/.claude/tests/` lists profiles.test.sh
#     and does NOT list this file or project-counters.test.sh.
#   * .claude/tests/project-counters.test.sh is ours and already parses gate
#     commands, so it is the tempting home - but it REQUIRES THE TOOLCHAIN by its
#     own header (stylua, selene, rojo, luau-lsp; a missing tool is a hard
#     failure and never a skip) and HARNESS-008 wired it to a required `harness`
#     gate. Folding a markdown assertion in there would make it unrunnable
#     because luau-lsp is absent - a vacuous-by-environment failure of exactly
#     the kind project-counters exists to abolish.
#   * the NAME pairs with project-counters deliberately: same subject (where a
#     gate's file count comes from), different artifact. project-counters pins
#     THIS PROJECT's .claude/harness/project.conf by RUNNING it; this suite pins
#     the DOCUMENT that conf was copied from, by READING it. bash, awk and
#     coreutils only - no toolchain, no network, no temp directory.
#   * scripts/selftest.sh globs .claude/tests/*.test.sh, so this is discovered
#     automatically, and CI's required `gates` job runs `bash scripts/selftest.sh`
#     (.github/workflows/gates.yml, "Harness self-test"). It is deliberately NOT
#     named by any `gate` line, so it does not run under `gates.sh --fast`.
#
# THE BOUNDARY THIS SUITE DRAWS, WHICH IS THE WHOLE DESIGN (Contract (c)):
#   A PRESCRIPTION is a line whose first pipe-field is `gate` - `gate | <id> |
#   ... | <command>`, indented or not. Those are the lines a project copies into
#   its project.conf, and they are the ONLY lines AC-1, AC-2 and AC-3 look at.
#   Everything else in the profile is PROSE: bullets, paragraphs, inline
#   backticks, and the indented `COUNT(dirs)` macro definition. Prose is out of
#   scope even when it contains a defective form verbatim, because AC-5 REQUIRES
#   four such paragraphs to survive - "`git ls-files` reads the index, not the
#   disk" is a bare `git ls-files` inside the sentence explaining why not to use
#   one. A guard that greps the whole file would fail the CORRECTED profile
#   precisely because AC-5 was satisfied, and the natural repair is to delete the
#   hazard, which is the one outcome this story must not produce.
#
#   The boundary is asserted, not claimed: see "the boundary itself" at the end.
#
#   Two lines were placed on the prose side deliberately, and the hole that
#   opens is closed by a POSITIVE requirement rather than by widening the scope:
#     - line ~44's worked counter-example (`n=$(git ls-files 'src/**/*.luau' ...`)
#       is a paragraph saying "this is wrong", so it is prose;
#     - line ~75's `COUNT(dirs)` macro definition is an indented code block, but
#       it is a definition, not a prescription.
#   A profile could therefore hide a bare `git ls-files` in a macro and delegate
#   to it from a clean-looking gate line. It cannot: AC-3 requires each of the
#   lint and typecheck GATE COMMANDS to contain the counting pipeline inline
#   (`ck_counter_present`), so a gate line that delegates has no pipeline and is
#   an offence. The macro is then unusable rather than forbidden, which is why
#   this suite does not care whether it survives as documentation.
#
# WHAT IT DOES NOT ASSERT: wording, section order, heading text, comment style,
# the `<dirs>` placeholder convention, or byte-agreement with project.conf.
# AC-6 is "agree in SHAPE", discharged by three structural comparisons and
# nothing else (Contract (b)). A byte comparison fails on the first honest
# divergence and gets deleted by the next person.
#
# AC-4, AC-5 and the EPIC-00 obligation assert that a CLAIM IS PRESENT, never how
# it is worded: each accepts a set of alternative phrasings, listed at the check.
# An assertion on exact phrasing turns every honest future edit into a red test
# and is deleted within two stories - the story's `## Notes` says so.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

PROFILE="$REPO_ROOT/.claude/skills/stack-profiles/reference/roblox-luau.md"
CONF="$REPO_ROOT/.claude/harness/project.conf"

# The shapes, taken out of the shipped project.conf rather than invented here.
# They are literals on purpose: a guard compared against a value it derived from
# the file under test asserts nothing (project-counters.test.sh makes the same
# point about its counts).
STYLUA_ANCHOR='debug: formatted '
PIPESTATUS_ANCHOR='PIPESTATUS[0]'
FULL_PATHSPEC='git ls-files --cached --others --exclude-standard'
LINT_VAR='GATE_LINT_TARGET'
TYPE_VAR='GATE_TYPE_TARGET'

# --- reading text ------------------------------------------------------------

_trim_var() { # <text> -> TRIMMED   (no fork; this runs per line of a 470-line file)
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  TRIMMED="$s"
}

# occurrences <haystack> <needle> -> OCCUR   Literal, non-overlapping. This is
# the same helper project-counters.test.sh uses for the same question ("does the
# command name its target twice?"); it is copied rather than shared because that
# suite shells out to four tools at load time and importing it would drag the
# whole toolchain requirement into a markdown assertion. _lib.sh is upstream's,
# so it is not a home for it either.
#
# It sets OCCUR instead of echoing, and gate_cmd_of / count_gates below do the
# same, for the reason project-counters spells out: a command substitution
# forks, and on Windows a fork is ~30 ms. Written with `$(occurrences ...)` on
# the hot path this suite took 30.5 s to read two text files; it is now ~2 s.
# Nothing about the assertions changed - measure before and after if you touch
# this, and do not reintroduce a fork inside scan_gates.
occurrences() {
  local h="$1" n="$2" c=0
  while :; do
    case "$h" in *"$n"*) c=$((c+1)); h="${h#*"$n"}" ;; *) break ;; esac
  done
  OCCUR="$c"
}

# gate_lines   stdin: document text.  stdout: one record per prescription,
# `<line number><TAB><gate id><TAB><trimmed line>`. This is the boundary, in
# code: a line is a prescription if and only if its first pipe-field is `gate`.
gate_lines() {
  local n=0 line t rest id
  while IFS= read -r line; do
    n=$((n+1))
    line="${line%$'\r'}"
    _trim_var "$line"; t="$TRIMMED"
    case "$t" in *'|'*) ;; *) continue ;; esac
    _trim_var "${t%%|*}"
    [ "$TRIMMED" = "gate" ] || continue
    rest="${t#*|}"
    _trim_var "${rest%%|*}"; id="$TRIMMED"
    printf '%s\t%s\t%s\n' "$n" "$id" "$t"
  done
}

gate_cmd_of() { # <trimmed gate line> -> GCMD, the command, fields 5..N (pipes intact)
  local rest="$1" i
  for i in 1 2 3 4; do rest="${rest#*|}"; done
  _trim_var "$rest"; GCMD="$TRIMMED"
}

# gl_of <text>   The parsed prescription list for a document. Computed ONCE per
# document and passed around; every scan below takes a list, never a document.
gl_of() { printf '%s\n' "$1" | gate_lines; }

count_gates() { # <gate line list> <id|ANY> -> NGATES
  local ln id raw c=0
  if [ -n "$1" ]; then
    while IFS=$'\t' read -r ln id raw; do
      [ "$2" = "ANY" ] || [ "$id" = "$2" ] || continue
      c=$((c+1))
    done <<< "$1"
  fi
  NGATES="$c"
}

conf_cmd() { # <id>   the command out of the shipped project.conf
  local ln id raw
  while IFS=$'\t' read -r ln id raw; do
    [ "$id" = "$1" ] || continue
    gate_cmd_of "$raw"
    printf '%s' "$GCMD"
    return 0
  done <<< "$GL_CONF"
  return 1
}

# --- offences ----------------------------------------------------------------

# AC-7: "names the offending line" is part of the criterion, so every offence
# carries the line NUMBER and the line TEXT. A message saying only "AC-2 failed"
# does not satisfy it.
offence() { # <line number> <line text> <reason>
  printf 'line %s: %s\n    %s\n' "$1" "$3" "$2"
}

# scan_gates <gate line list> <id|ANY> <check fn>   Runs the check over every
# matching prescription and prints whatever offences it finds. Empty == clean.
scan_gates() {
  local ln id raw
  [ -n "$1" ] || return 0
  while IFS=$'\t' read -r ln id raw; do
    [ "$2" = "ANY" ] || [ "$id" = "$2" ] || continue
    gate_cmd_of "$raw"
    "$3" "$ln" "$id" "$raw" "$GCMD"
  done <<< "$1"
}

# Each check takes <line number> <id> <raw line> <command>.

ck_format_anchor() {
  case "$4" in
    *"$STYLUA_ANCHOR"*) ;;
    *) offence "$1" "$3" "the format gate does not take its count from stylua's own output: no '$STYLUA_ANCHOR' in the command" ;;
  esac
}

ck_format_status() {
  case "$4" in
    *"$PIPESTATUS_ANCHOR"*) ;;
    *) offence "$1" "$3" "the format gate does not take its exit status from \${$PIPESTATUS_ANCHOR}, so its correctness is borrowed from the runner's shell options" ;;
  esac
}

ck_format_no_second_count() {
  local m
  for m in 'git ls-files' 'COUNT(' 'find ' 'wc -l'; do
    case "$4" in
      *"$m"*) offence "$1" "$3" "the format gate counts its inputs BESIDE the tool: the command contains '$m', and stylua --check -v already prints one line per file it read" ;;
    esac
  done
}

_ck_target_named_once() { # <ln> <raw> <cmd> <var>
  local open n r
  open="\${$4:="
  occurrences "$3" "$open"; n="$OCCUR"
  if [ "$n" -ne 1 ]; then
    offence "$1" "$2" "the target is not named through a single '$open...}': found $n, want exactly 1"
    return 0
  fi
  occurrences "$3" "$4"; r="$OCCUR"
  if [ "$r" -lt 2 ]; then
    offence "$1" "$2" "'$open...}' is assigned but \$$4 is never read back, so the counter is not sharing the tool's target"
  fi
}

_ck_target_list_once() { # <ln> <raw> <cmd> <var>
  local open def t
  open="\${$4:="
  case "$3" in
    *"$open"*) ;;
    *) offence "$1" "$2" "no '$open...}' to read the target list out of, so the tool's target and the counter's cannot be the same by construction"
       return 0 ;;
  esac
  def="${3#*"$open"}"
  def="${def%%\}*}"
  occurrences "$3" "$def"; t="$OCCUR"
  if [ "$t" -ne 1 ]; then
    offence "$1" "$2" "the target list '$def' is named $t times, want exactly 1 - a second enumeration is the HARNESS-006 defect"
    return 0
  fi
}

ck_target_lint() { _ck_target_named_once "$1" "$3" "$4" "$LINT_VAR"; }
ck_target_type() { _ck_target_named_once "$1" "$3" "$4" "$TYPE_VAR"; }
ck_list_lint()   { _ck_target_list_once  "$1" "$3" "$4" "$LINT_VAR"; }
ck_list_type()   { _ck_target_list_once  "$1" "$3" "$4" "$TYPE_VAR"; }

ck_no_bare_lsfiles() {
  local a b
  occurrences "$4" 'git ls-files'; a="$OCCUR"
  occurrences "$4" "$FULL_PATHSPEC"; b="$OCCUR"
  if [ "$a" -ne "$b" ]; then
    offence "$1" "$3" "uses a bare 'git ls-files' ($a occurrence(s), only $b carrying --cached --others --exclude-standard): bare ls-files reads the index and misses a story's own new files until they are committed"
  fi
}

ck_no_find() {
  case "$4" in
    *'find '*) offence "$1" "$3" "enumerates with 'find', which sweeps in gitignored build output - HARNESS-006 measured 39 against the tools' 38" ;;
  esac
}

ck_counter_present() {
  local b
  occurrences "$4" "$FULL_PATHSPEC"; b="$OCCUR"
  if [ "$b" -lt 1 ]; then
    offence "$1" "$3" "has no counting pipeline in the command itself: no '$FULL_PATHSPEC'. A gate that delegates its count to a macro can name its target twice out of sight"
  fi
}

# verdict <text> <id|ANY> <check fn>   ok | BAD | no-gate.  The no-gate arm
# matters: with no matching prescription a scan is silently clean, and "the
# profile deleted the gate" would read as agreement.
verdict() {
  local o
  count_gates "$1" "$2"
  if [ "$2" != "ANY" ] && [ "$NGATES" -eq 0 ]; then printf 'no-gate'; return 0; fi
  o="$(scan_gates "$1" "$2" "$3")"
  if [ -n "$o" ]; then printf 'BAD'; else printf 'ok'; fi
}

# --- claims in prose ---------------------------------------------------------

# near <text> <window> <spec>   Is there a run of <window> consecutive lines
# containing all of the groups in <spec>?  Groups are separated by `;;` and
# alternative phrasings within a group by `@@`; matching is literal (index(),
# not a regex) and case-insensitive. Prints the first such line number.
#
# A WINDOW rather than a bullet or a paragraph: it asserts that the tokens of a
# hazard sit TOGETHER, which is what "the hazard is still stated" means, without
# constraining GREEN to keep them as a bullet list. Whole-document presence would
# be too weak - `pipefail` appearing anywhere would satisfy a deleted hazard.
near() {
  printf '%s\n' "$1" | awk -v w="$2" -v spec="$3" '
    BEGIN { ng = split(spec, G, ";;") }
    { buf[NR] = tolower($0) }
    END {
      for (i = 1; i <= NR; i++) {
        s = ""
        for (j = i; j < i + w && j <= NR; j++) s = s "\n" buf[j]
        ok = 1
        for (g = 1; g <= ng; g++) {
          na = split(G[g], A, "@@"); hit = 0
          for (a = 1; a <= na; a++) if (index(s, tolower(A[a]))) { hit = 1; break }
          if (!hit) { ok = 0; break }
        }
        if (ok) { print i; exit }
      }
    }'
}

assert_claim() { # <what> <text> <window> <spec>
  local at; at="$(near "$2" "$3" "$4")"
  if [ -n "$at" ]; then _ok "$1"
  else _bad "$1" "no run of $3 consecutive lines carries this claim.
Any ONE phrasing per \`;;\` group satisfies it - the wording is GREEN's choice:
$(printf '%s\n' "$4" | tr ';' '\n' | sed '/^$/d' | sed 's/^/  group: /')"
  fi
}

missing_tokens() { # <text> <token>...
  local text="$1" t out=""; shift
  for t in "$@"; do
    printf '%s\n' "$text" | grep -qiF -- "$t" || out="$out$t
"
  done
  printf '%s' "$out"
}

# --- load --------------------------------------------------------------------

describe "preconditions"

if [ ! -f "$PROFILE" ]; then
  _bad "the roblox-luau profile exists" "not found: $PROFILE"
  summary "profile-counters"; exit 1
fi
if [ ! -f "$CONF" ]; then
  _bad "project.conf exists (AC-6 compares against it)" "not found: $CONF"
  summary "profile-counters"; exit 1
fi

PROFILE_TEXT="$(cat "$PROFILE")"
CONF_TEXT="$(cat "$CONF")"
GL_PROFILE="$(gl_of "$PROFILE_TEXT")"
GL_CONF="$(gl_of "$CONF_TEXT")"

_ok "the roblox-luau profile exists"
_ok "project.conf exists (AC-6 compares against it)"

# Without this the scans below are silently clean on a profile that deleted the
# gate table, and every AC-1 to AC-3 assertion becomes vacuous.
have() { count_gates "$1" "$2"; if [ "$NGATES" -ge 1 ]; then printf 'yes'; else printf 'no'; fi; }
assert_eq "the profile prescribes a format, a lint and a typecheck gate command" \
  "format=yes lint=yes typecheck=yes" \
  "format=$(have "$GL_PROFILE" format) lint=$(have "$GL_PROFILE" lint) typecheck=$(have "$GL_PROFILE" typecheck)"
assert_eq "project.conf prescribes the same three" \
  "format=yes lint=yes typecheck=yes" \
  "format=$(have "$GL_CONF" format) lint=$(have "$GL_CONF" lint) typecheck=$(have "$GL_CONF" typecheck)"

# ---------------------------------------------------------------------------
# AC-1 - the format count is STYLUA'S OWN, not an enumeration beside it.
describe "AC-1  the format gate takes its count from the tool"

assert_eq "every format gate command counts stylua's own 'debug: formatted' lines" \
  "" "$(scan_gates "$GL_PROFILE" format ck_format_anchor)"
assert_eq "every format gate command takes its status from \${PIPESTATUS[0]}" \
  "" "$(scan_gates "$GL_PROFILE" format ck_format_status)"
assert_eq "no format gate command enumerates its inputs beside the tool" \
  "" "$(scan_gates "$GL_PROFILE" format ck_format_no_second_count)"

# ---------------------------------------------------------------------------
# AC-2 - the defect the story exists for. The target list is named ONCE and the
# counter reads it, so the tool's target and the counter's cannot disagree.
describe "AC-2  lint and typecheck name their target exactly once"

assert_eq "every lint gate command names its target through a single \${$LINT_VAR:=...} the counter reads" \
  "" "$(scan_gates "$GL_PROFILE" lint ck_target_lint)"
assert_eq "every lint gate command names the target path list exactly once" \
  "" "$(scan_gates "$GL_PROFILE" lint ck_list_lint)"
assert_eq "every typecheck gate command names its target through a single \${$TYPE_VAR:=...} the counter reads" \
  "" "$(scan_gates "$GL_PROFILE" typecheck ck_target_type)"
assert_eq "every typecheck gate command names the target path list exactly once" \
  "" "$(scan_gates "$GL_PROFILE" typecheck ck_list_type)"

# ---------------------------------------------------------------------------
# AC-3 - the pathspec. Scoped to prescriptions; prose may say `git ls-files` as
# often as it likes, and AC-5 requires that it does.
describe "AC-3  the counting pipeline uses --cached --others --exclude-standard"

assert_eq "no gate command in the profile uses a bare 'git ls-files'" \
  "" "$(scan_gates "$GL_PROFILE" ANY ck_no_bare_lsfiles)"
assert_eq "no gate command in the profile enumerates with 'find'" \
  "" "$(scan_gates "$GL_PROFILE" ANY ck_no_find)"
assert_eq "every lint gate command carries the counting pipeline inline" \
  "" "$(scan_gates "$GL_PROFILE" lint ck_counter_present)"
assert_eq "every typecheck gate command carries the counting pipeline inline" \
  "" "$(scan_gates "$GL_PROFILE" typecheck ck_counter_present)"

# ---------------------------------------------------------------------------
# AC-4 - the sentence that GENERATED the three defective commands. Fixing the
# commands without fixing this means the next gate added to the profile
# reintroduces the defect.
describe "AC-4  the prose prefers the tool's own count"

assert_eq "the profile no longer says to make the gate command count its own inputs" \
  "" "$(grep -niF -- 'count its own inputs' "$PROFILE" || true)"

# Accepted phrasings are listed in the spec and in the failure message. This is a
# CLAIM check, not a wording check: any one alternative per group satisfies it.
CLAIM_PREFER="tool's own@@tool"$'’'"s own@@'s own count@@'s own output@@prefer the tool@@read the count out of the tool@@the tool already counts"
assert_claim "the profile says to prefer the tool's own count" "$PROFILE_TEXT" 4 "$CLAIM_PREFER"

CLAIM_DERIVE="derive@@derived@@deriving@@derivation;;has none@@has no count@@no count of its own@@no per-file@@does not print@@prints no@@emits none"
assert_claim "the profile says a count is derived only where the tool has none" "$PROFILE_TEXT" 6 "$CLAIM_DERIVE"

# ---------------------------------------------------------------------------
# AC-5 - four hazards, each with its OWN assertion so a failure names which one.
# Each was paid for by a real failure and HARNESS-006 re-confirmed all four.
# A tidy-minded rewrite deletes them as clutter; that is what this block refuses.
describe "AC-5  all four documented hazards survive"

# The alternations below are deliberately NOT generous, and one of them was
# tightened because a probe caught it. `matches zero` was an accepted phrasing
# for hazard 1 and `first argument of each gate` for hazard 4 - both are
# satisfied by a sentence stating the OPPOSITE of the hazard, and the hazard-4
# probe (`first token` -> `first argument`) duly left the suite green. A needle
# that its own mutation satisfies is a test that cannot fail.
assert_claim "hazard 1: a git pathspec's '**/' never matches zero directories" \
  "$PROFILE_TEXT" 8 '**/*.luau;;ls-files;;one or more directories@@never zero@@never matches zero'
assert_claim "hazard 2: git ls-files reads the index, not the disk (hence [ -e \"\$f\" ])" \
  "$PROFILE_TEXT" 8 '[ -e "$f" ];;index, not the disk@@index rather than the disk@@reads the index@@the index and not the disk'
assert_claim "hazard 3: a grep stage exits 1 on an empty tree and takes the && chain with it under pipefail" \
  "$PROFILE_TEXT" 8 'pipefail;;empty tree@@an empty target@@empty target;;exit 0@@exits 1@@exit 1'
assert_claim "hazard 4: doctor.sh reads the FIRST TOKEN of a gate command as the executable" \
  "$PROFILE_TEXT" 8 'doctor.sh;;first token@@first word'

# ---------------------------------------------------------------------------
# EPIC-00 is DONE and two of its done-when rows cite text inside this file
# (story Contract (d)). A tidy rewrite un-delivers a closed epic without a word.
describe "EPIC-00's evidence, which lives inside this file"

assert_eq "the Verified banner still names all seven pinned tools and both platform verdicts" \
  "" "$(missing_tokens "$PROFILE_TEXT" \
        'Verified 2026-09-15' 'Rokit 1.2.0' 'Rojo 7.7.0' 'Wally 0.3.2' \
        'Lune 0.10.5' 'Selene 0.31.0' 'StyLua 2.5.2' 'luau-lsp 1.69.0' \
        'Linux verified 2026-09-16' 'macOS is still unverified')"
assert_claim "... and they are one banner, not scattered across the document" \
  "$PROFILE_TEXT" 10 'Verified 2026-09-15;;Rokit 1.2.0;;luau-lsp 1.69.0;;Linux verified 2026-09-16;;macOS is still unverified'

PREREQ_LINE="$(printf '%s\n' "$PROFILE_TEXT" | grep -n '^## Prerequisites' | head -1)"
PREREQ_LINE="${PREREQ_LINE%%:*}"
ROKIT_CURL="$(near "$PROFILE_TEXT" 1 'curl;;rokit;;install.sh')"
if [ -z "$PREREQ_LINE" ]; then
  _bad "the Rokit curl install line survives under Prerequisites" "no '## Prerequisites' heading in the profile"
elif [ -z "$ROKIT_CURL" ]; then
  _bad "the Rokit curl install line survives under Prerequisites" \
    "no single line carries all of: curl, rokit, install.sh.
EPIC-00 RESOLVED this line's UNVERIFIED marker rather than deleting it."
elif [ "$ROKIT_CURL" -le "$PREREQ_LINE" ]; then
  _bad "the Rokit curl install line survives under Prerequisites" \
    "found at line $ROKIT_CURL, which is above '## Prerequisites' at line $PREREQ_LINE"
else
  _ok "the Rokit curl install line survives under Prerequisites"
fi

# ---------------------------------------------------------------------------
# AC-6 - "agree in SHAPE", made mechanical by Contract (b): three structural
# comparisons and NOTHING ELSE. Not byte-identity: the profile legitimately uses
# <dirs> placeholders and prose where the conf has real paths.
#
# Each comparison's expected value is a LITERAL, never the conf's own verdict.
# Reading the oracle out of the file under comparison would make a regression in
# project.conf look like agreement.
describe "AC-6  project.conf, the side known to have got it right"

assert_eq "conf: the format gate counts from stylua's own output" \
  "" "$(scan_gates "$GL_CONF" format ck_format_anchor)"
assert_eq "conf: the format gate takes its status from \${PIPESTATUS[0]}" \
  "" "$(scan_gates "$GL_CONF" format ck_format_status)"
assert_eq "conf: lint and typecheck name their target once, through \${GATE_*_TARGET:=...}" \
  "" "$(scan_gates "$GL_CONF" lint ck_target_lint)$(scan_gates "$GL_CONF" lint ck_list_lint)$(scan_gates "$GL_CONF" typecheck ck_target_type)$(scan_gates "$GL_CONF" typecheck ck_list_type)"
assert_eq "conf: both counters use --cached --others --exclude-standard" \
  "" "$(scan_gates "$GL_CONF" ANY ck_no_bare_lsfiles)$(scan_gates "$GL_CONF" lint ck_counter_present)$(scan_gates "$GL_CONF" typecheck ck_counter_present)"

describe "AC-6  the profile and project.conf agree in shape"

assert_eq "comparison 1 - format: both count from 'debug: formatted' and both take status from \${PIPESTATUS[0]}" \
  "conf=ok/ok profile=ok/ok" \
  "conf=$(verdict "$GL_CONF" format ck_format_anchor)/$(verdict "$GL_CONF" format ck_format_status) profile=$(verdict "$GL_PROFILE" format ck_format_anchor)/$(verdict "$GL_PROFILE" format ck_format_status)"

assert_eq "comparison 2 - lint/typecheck: both name the target through a single \${GATE_*_TARGET:=...}, path list once" \
  "conf=ok/ok/ok/ok profile=ok/ok/ok/ok" \
  "conf=$(verdict "$GL_CONF" lint ck_target_lint)/$(verdict "$GL_CONF" lint ck_list_lint)/$(verdict "$GL_CONF" typecheck ck_target_type)/$(verdict "$GL_CONF" typecheck ck_list_type) profile=$(verdict "$GL_PROFILE" lint ck_target_lint)/$(verdict "$GL_PROFILE" lint ck_list_lint)/$(verdict "$GL_PROFILE" typecheck ck_target_type)/$(verdict "$GL_PROFILE" typecheck ck_list_type)"

assert_eq "comparison 3 - both counters use 'git ls-files --cached --others --exclude-standard'" \
  "conf=ok/ok/ok profile=ok/ok/ok" \
  "conf=$(verdict "$GL_CONF" ANY ck_no_bare_lsfiles)/$(verdict "$GL_CONF" lint ck_counter_present)/$(verdict "$GL_CONF" typecheck ck_counter_present) profile=$(verdict "$GL_PROFILE" ANY ck_no_bare_lsfiles)/$(verdict "$GL_PROFILE" lint ck_counter_present)/$(verdict "$GL_PROFILE" typecheck ck_counter_present)"

# ---------------------------------------------------------------------------
# AC-7 - "fails and NAMES THE OFFENDING LINE". Asserted against a fixture rather
# than against the real profile, because the real profile stops being defective
# in GREEN and this property must keep being checked afterwards.
describe "AC-7  a reintroduced second enumeration is named, with its line"

DIRTY_FIXTURE="$(cat <<'EOF'
# fixture: the defective prescription is on line 4
Prose about `git ls-files` reading the index, not the disk, must be ignored.

    gate | lint | required | . | selene src tests lune && COUNT(src tests lune) && echo "selene over $n files"
EOF
)"
GL_DIRTY="$(gl_of "$DIRTY_FIXTURE")"

DIRTY_OFF="$(scan_gates "$GL_DIRTY" lint ck_target_lint
             scan_gates "$GL_DIRTY" lint ck_list_lint
             scan_gates "$GL_DIRTY" lint ck_counter_present
             scan_gates "$GL_DIRTY" ANY ck_no_bare_lsfiles)"

assert_contains "a COUNT(<paths>) prescription is reported with its line number" "line 4:" "$DIRTY_OFF"
assert_contains "... and with the offending line's own text" \
  'COUNT(src tests lune)' "$DIRTY_OFF"

# The regression AC-7 is really aimed at is not today's form - GREEN deletes
# that - but a second enumeration added back AFTER the fix, to a command that
# already looks right. Today's form never reaches the occurrence count at all:
# with no ${GATE_LINT_TARGET:=...} there is no target list to count, so
# _ck_target_list_once reports the missing assignment and stops. Without this
# fixture the counting arm - the sharpest check in the suite - would ship
# unexercised, and a future edit is exactly what it exists to catch.
REGRESSED_FIXTURE="$(cat <<'EOF'
# fixture: the CORRECTED form with a second enumeration added back, on line 2
    gate | lint | required | . | selene ${GATE_LINT_TARGET:=src tests lune} && n=$(git ls-files --cached --others --exclude-standard -- src tests lune | wc -l) && echo "selene over $n files"
EOF
)"
GL_REGRESSED="$(gl_of "$REGRESSED_FIXTURE")"

REGRESSED_OFF="$(scan_gates "$GL_REGRESSED" lint ck_target_lint
                 scan_gates "$GL_REGRESSED" lint ck_list_lint
                 scan_gates "$GL_REGRESSED" lint ck_counter_present
                 scan_gates "$GL_REGRESSED" ANY ck_no_bare_lsfiles)"

assert_contains "a second enumeration added back to a corrected command is reported with its line number" \
  "line 2:" "$REGRESSED_OFF"
assert_contains "... and the reason says how many times the target was named" \
  "is named 2 times" "$REGRESSED_OFF"
assert_contains "... and quotes the target list it counted" \
  "'src tests lune'" "$REGRESSED_OFF"

# ---------------------------------------------------------------------------
# THE BOUNDARY ITSELF (Contract (c)). Without these three cases "AC-2 and AC-3
# are scoped to prescriptions, never to prose" is a claim in a comment.
describe "the boundary: prose that shows a defective form is not a prescription"

PROSE_FIXTURE="$(cat <<'EOF'
# fixture: every defective form, in prose, plus one CORRECT prescription
The obvious version - `n=$(git ls-files 'src/**/*.luau' | wc -l); selene src tests` - is wrong.

- **`git ls-files` reads the index, not the disk.** `[ -e "$f" ]` fixes it.
- A `find src tests lune -name '*.luau'` sweep counts gitignored build output.
- `COUNT(src tests lune)` names the target twice, by construction.

Let `COUNT(dirs)` stand for the counting pipeline above:

    n=$(git ls-files -- <dirs> | while IFS= read -r f; do echo x; done | wc -l)

    gate | lint | required | . | selene ${GATE_LINT_TARGET:=src tests lune} && n=$(git ls-files --cached --others --exclude-standard -- $GATE_LINT_TARGET | wc -l) && echo "selene over $n files"
EOF
)"
GL_PROSE="$(gl_of "$PROSE_FIXTURE")"

assert_eq "a document whose prose contains bare git ls-files, find, COUNT() and a **/ pathspec is clean" \
  "" "$(scan_gates "$GL_PROSE" lint ck_target_lint
        scan_gates "$GL_PROSE" lint ck_list_lint
        scan_gates "$GL_PROSE" lint ck_counter_present
        scan_gates "$GL_PROSE" ANY ck_no_bare_lsfiles
        scan_gates "$GL_PROSE" ANY ck_no_find)"

# The same question against the REAL prose rather than a hand-written sample:
# today's profile with ONLY its three gate lines replaced by project.conf's.
# Every hazard paragraph, the line-44 counter-example and the COUNT(dirs) macro
# are present verbatim. If the scope leaked into prose, this goes red - which is
# exactly the failure that would tempt the next person to delete a hazard.
corrected_profile() {
  local line t rest id
  while IFS= read -r line; do
    line="${line%$'\r'}"
    _trim_var "$line"; t="$TRIMMED"; id=""
    case "$t" in
      *'|'*) _trim_var "${t%%|*}"
             if [ "$TRIMMED" = "gate" ]; then rest="${t#*|}"; _trim_var "${rest%%|*}"; id="$TRIMMED"; fi ;;
    esac
    case "$id" in
      format)    printf '    gate | format    | optional | . | %s\n' "$CONF_FORMAT" ;;
      lint)      printf '    gate | lint      | required | . | %s\n' "$CONF_LINT" ;;
      typecheck) printf '    gate | typecheck | required | . | %s\n' "$CONF_TYPECHECK" ;;
      *)         printf '%s\n' "$line" ;;
    esac
  done < "$PROFILE"
}

CONF_FORMAT="$(conf_cmd format)"
CONF_LINT="$(conf_cmd lint)"
CONF_TYPECHECK="$(conf_cmd typecheck)"
CORRECTED="$(corrected_profile)"
GL_CORRECTED="$(gl_of "$CORRECTED")"

assert_eq "today's profile with only its gate lines corrected is clean, hazard paragraphs and all" \
  "" "$(scan_gates "$GL_CORRECTED" format ck_format_anchor
        scan_gates "$GL_CORRECTED" format ck_format_status
        scan_gates "$GL_CORRECTED" format ck_format_no_second_count
        scan_gates "$GL_CORRECTED" lint ck_target_lint
        scan_gates "$GL_CORRECTED" lint ck_list_lint
        scan_gates "$GL_CORRECTED" lint ck_counter_present
        scan_gates "$GL_CORRECTED" typecheck ck_target_type
        scan_gates "$GL_CORRECTED" typecheck ck_list_type
        scan_gates "$GL_CORRECTED" typecheck ck_counter_present
        scan_gates "$GL_CORRECTED" ANY ck_no_bare_lsfiles
        scan_gates "$GL_CORRECTED" ANY ck_no_find)"

# ... and the clean verdict above is not clean because the hazards went missing.
assert_eq "and that same corrected document still states all four hazards" \
  "1111" \
  "$( [ -n "$(near "$CORRECTED" 8 '**/*.luau;;ls-files;;one or more directories@@never zero@@never matches zero')" ] && printf 1 || printf 0
      [ -n "$(near "$CORRECTED" 8 '[ -e "$f" ];;index, not the disk@@index rather than the disk@@reads the index@@the index and not the disk')" ] && printf 1 || printf 0
      [ -n "$(near "$CORRECTED" 8 'pipefail;;empty tree@@an empty target@@empty target;;exit 0@@exits 1@@exit 1')" ] && printf 1 || printf 0
      [ -n "$(near "$CORRECTED" 8 'doctor.sh;;first token@@first word')" ] && printf 1 || printf 0 )"

summary "profile-counters"
