#!/usr/bin/env bash
# What to run a story with, and on which model.
#
#   bash scripts/plan.sh <id>           both answers, for a human
#   bash scripts/plan.sh models <id>    PHASE<TAB>agent<TAB>model<TAB>why
#   bash scripts/plan.sh next <id>      the command to drive it with, and why
#
# Two questions that used to be asked of a person every time. A question asked
# every time stops being answered and starts being habit, and the model question
# in particular has a rule about it: `rules.md` says a model choice with no
# recorded verdict is folklore. The policy is in `.claude/harness/models.conf`
# with a reason per row; this reads it and applies it to one story.
#
# It RECOMMENDS. Neither answer is enforced anywhere, and neither should be:
# the story's own `## Model guidance` outranks the policy file, and a human who
# wants the other command has better information than a threshold does. What
# this removes is not the decision, it is having to reconstruct the reasoning
# from scratch on every story.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export CLAUDE_PROJECT_DIR="$ROOT"
. "$ROOT/.claude/hooks/lib.sh"

CONF="$ROOT/.claude/harness/models.conf"
PHASES="$ROOT/.claude/harness/phases.conf"
STORIES="$ROOT/docs/backlog/stories"

die() { printf 'plan: %s\n' "$1" >&2; exit 2; }

story_file() {
  local f="$STORIES/$1.md"
  [ -f "$f" ] || die "no story at docs/backlog/stories/$1.md"
  printf '%s' "$f"
}

# section <file> <heading-prefix>   Body of "## <prefix>..." up to the next "## ".
section() {
  awk -v h="## $2" 'index($0, h) == 1 { on=1; next } on && /^## / { exit } on { print }' "$1"
}

# Comments are the template; what matters is whether a person wrote anything.
strip_comments() {
  awk '{ s = s $0 "\n" }
       END {
         while ((i = index(s, "<!--")) > 0) {
           r = substr(s, i); j = index(r, "-->")
           if (j == 0) { s = substr(s, 1, i - 1); break }
           s = substr(s, 1, i - 1) substr(r, j + 3)
         }
         printf "%s", s
       }'
}
# ONE awk, not `strip_comments | grep -q`. This helper was lifted from
# check-boundaries.sh when this script was written, and its defect came with it:
# an awk that buffers to END feeding a grep that exits at the first match, so the
# writer dies of SIGPIPE and `pipefail` turns 141 into "no content". 50,000 bytes
# passed; 200,000 did not.
#
# The consequence here is quieter than a refused PR and worse for it. A thorough
# contract - the kind the RED row exists to reward - reads as ABSENT, the
# no-contract exception fires, and RED silently moves to the stronger model.
# Nothing fails; the story just runs on a model nobody chose.
has_content() {
  awk '{ s = s $0 "\n" }
       END {
         while ((i = index(s, "<!--")) > 0) {
           r = substr(s, i); j = index(r, "-->")
           if (j == 0) { s = substr(s, 1, i - 1); break }
           s = substr(s, 1, i - 1) substr(r, j + 3)
         }
         exit (s ~ /[^[:space:]]/) ? 0 : 1
       }'
}

conf_rows() { grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$CONF"; }
field() { printf '%s' "$1" | awk -F'|' -v n="$2" '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $n); print $n }'; }

# --- the model plan ---------------------------------------------------------

# True when the contract names paths and EVERY one of them is a path the lock
# will not freeze. `harness` is in every phase's allowed list in phases.conf, and
# `.claude/tests/*`, `scripts/*` and `.claude/hooks/*` all classify as `harness`
# - so for a story that maintains the harness itself, RED may write the
# mechanism and GREEN may rewrite the frozen tests with nothing to stop either.
#
# That changes what the RED row rests on. Everywhere else the contract is an aid
# to the model and the LOCK is the enforcement; here the contract is the
# enforcement, the only one there is. Reported from a consuming project, which
# measured gates.sh --fast at 13/13 with identical counts across a GREEN that
# added a script, a config file and 25 assertions.
#
# One source path is enough for the lock to bite, so this needs ALL of them:
# otherwise every story that touches a helper script would trip it.
#
# WHICH PATHS (HARNESS-014). The scan below answers "does the Contract MENTION a
# path that classifies as source?" when the question it stands in for is "does
# this story WRITE one?". HARNESS-012 - both of whose files are `harness` - was
# scanned into sixteen tokens of which five classified as `source`: `src/main.ts`
# (a fixture inside a throwaway repository), `5.3.15` (a bash version out of a
# measurement note), `i.e` (English), and the bare filenames `classify.sh` and
# `mutate.sh`. The exception fell silently on the WEAK side, for exactly the
# story it was written for.
#
# So when the Contract carries a `### Files` table, the path list is that
# table's FIRST COLUMN and nothing else in the section - the repository's own
# header row has `classify.sh` in its second column, so a reader of the whole
# table reproduces the bug. With no table the fallback scan stands, byte for
# byte, because it is what every story written before this one relies on.
# Narrowing its regex is a separate question; what makes it safe to leave alone
# is that the verdict is now SAID OUT LOUD - see lock_coverage_line.

# classify_many   One repo-relative path per line on stdin, "<category><TAB><path>"
# per line out. classify() from lib.sh, in one awk for the whole list rather than
# four processes per path: a fork costs ~50ms on this machine and a contract can
# name sixteen paths. The `ignored` check is classify()'s, not classify_stdin's,
# and only a `source` verdict can become one.
classify_many() {
  local cat p
  classify_stdin | while IFS=$'\t' read -r cat p; do
    [ "$cat" = "source" ] && is_ignored "$p" && cat=ignored
    printf '%s\t%s\n' "$cat" "$p"
  done
}

# declared_paths <contract-body>   The first column of the `### Files` table's
# body rows. Rows are skipped BY CONTENT, not by position: a header whose first
# cell is `Path`, a `|---|` separator, an empty cell. `### Files` is not a
# section terminator - section() splits on `^## `, so the heading is inside the
# Contract body already - and the table ends at the next `###` heading.
declared_paths() {
  printf '%s\n' "$1" | awk '
    /^###[[:space:]]/ { infiles = ($0 ~ /^###[[:space:]]+Files([[:space:]]|$)/); next }
    !infiles { next }
    {
      line = $0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (index(line, "|") != 1) next
      sub(/^\|/, "", line)
      col = line; sub(/\|.*/, "", col)
      gsub(/`/, "", col)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", col)
      if (col == "" || col == "Path") next
      if (col ~ /^:?-{3,}:?$/) next
      print col
    }'
}

# The decision, computed once per story file and cached: cmd_both and cmd_write
# each need both the verdict (through cmd_models) and the line, and the scan
# costs a classify pass.
LC_FILE=""        # the file these values describe, or "" for none yet
LC_ORIGIN=none    # declared | scanned | none
LC_COUNT=0        # how many paths were considered
LC_OFFENDERS=""   # "<path><TAB><category>" per line, in path-list order
LC_OFFCOUNT=0     # how many of them there are
LC_UNENFORCED=0

lock_scan() { # <file>
  [ "$LC_FILE" = "$1" ] && return 0
  LC_FILE="$1"; LC_ORIGIN=none; LC_COUNT=0; LC_OFFENDERS=""; LC_OFFCOUNT=0; LC_UNENFORCED=0

  local body paths p c enforced=0 TAB NL; TAB=$'\t'; NL=$'\n'
  body="$(section "$1" "Contract" | strip_comments)"
  paths="$(declared_paths "$body")"
  if [ -n "$paths" ]; then
    LC_ORIGIN=declared
  else
    paths="$(printf '%s\n' "$body" \
      | grep -oE '\.claude/[A-Za-z0-9_./-]+|[A-Za-z0-9_][A-Za-z0-9_./-]*\.[A-Za-z0-9]+' | sort -u)"
    LC_ORIGIN=scanned
  fi

  while IFS=$'\t' read -r c p; do
    [ -n "$p" ] || continue
    LC_COUNT=$((LC_COUNT + 1))
    case "$c" in
      harness|docs|ignored) ;;
      *) enforced=1; LC_OFFCOUNT=$((LC_OFFCOUNT + 1))
         LC_OFFENDERS="$LC_OFFENDERS$p$TAB$c$NL" ;;
    esac
  done <<< "$(printf '%s\n' "$paths" | classify_many)"

  # The fallback's own rule, unchanged in effect: a contract naming no paths at
  # all does not trigger the exception. It is ONE line rather than an early
  # `[ -n "$paths" ] || return 1` as well - two guards for one rule means either
  # can be mutated with the other still returning the right verdict, and a rule
  # no mutation can break is a rule no test pins. Break this one and T-9 goes
  # red, which is the probe RED ran.
  [ "$LC_COUNT" -gt 0 ] || { LC_ORIGIN=none; return 0; }
  [ "$enforced" = 0 ] && LC_UNENFORCED=1
  return 0
}

contract_unenforced() { # <file>
  lock_scan "$1"
  [ "$LC_UNENFORCED" = 1 ]
}

# lock_offenders   Up to three `path` (category), then ` (+N more)`.
lock_offenders() {
  local p c n=0 extra=0 out=""
  while IFS=$'\t' read -r p c; do
    [ -n "$p" ] || continue
    n=$((n + 1))
    if [ "$n" -le 3 ]; then
      [ -n "$out" ] && out="$out, "
      out="$out\`$p\` ($c)"
    else
      extra=$((extra + 1))
    fi
  done <<< "$LC_OFFENDERS"
  [ "$extra" -gt 0 ] && out="$out (+$extra more)"
  printf '%s' "$out"
}

# lock_coverage_line <file>   One sentence, no indentation, saying which of the
# two sources the paths came from, whether the exception applied or was
# suppressed, and - when suppressed - what suppressed it and what classify.sh
# called it. ONE function, called by cmd_both and cmd_write, so the two cannot
# drift; never by cmd_models, whose stdout three callers parse field-wise and
# would take a note for a row.
#
# The three verdict keywords are mutually non-matching substrings on purpose:
# rules.md carries four cases of a needle satisfied by a string meaning the
# opposite, so `APPLIES`, `SUPPRESSED by ` and `NOT CONSIDERED` are chosen so
# that no anchored needle for one can match another.
lock_coverage_line() { # <file>
  lock_scan "$1"
  local src
  case "$LC_ORIGIN" in
    declared) src="declared in the Contract's ### Files table" ;;
    scanned)  src="scanned from the Contract text" ;;
    *) printf 'Lock coverage: NOT CONSIDERED — this contract names no paths.\n'; return 0 ;;
  esac
  if [ "$LC_UNENFORCED" = 1 ]; then
    printf 'Lock coverage: APPLIES — all %s path(s) %s are harness/docs/ignored, so RED stays on the stronger model.\n' \
      "$LC_COUNT" "$src"
  else
    local subj=it; [ "$LC_OFFCOUNT" -gt 1 ] && subj=them
    printf 'Lock coverage: SUPPRESSED by %s, %s — the phase lock freezes %s, so RED follows the plain plan.\n' \
      "$(lock_offenders)" "$src" "$subj"
  fi
}

cmd_models() {
  local file id; id="$1"; file="$(story_file "$id")"
  local type contract_has=0 unenforced=0
  type="$(frontmatter_value "$file" type)"; [ -n "$type" ] || type=feature
  section "$file" "Contract" | has_content && contract_has=1
  contract_unenforced "$file" && unenforced=1

  local row ph agent model why
  while IFS= read -r row; do
    case "$(field "$row" 1)" in model) ;; *) continue ;; esac
    ph="$(field "$row" 2)"; agent="$(field "$row" 3)"
    model="$(field "$row" 4)"; why="$(field "$row" 5)"

    # Exceptions first, first match wins.
    local erow econd emodel ewhy
    while IFS= read -r erow; do
      case "$(field "$erow" 1)" in except) ;; *) continue ;; esac
      [ "$(field "$erow" 2)" = "$ph" ] || continue
      econd="$(field "$erow" 3)"; emodel="$(field "$erow" 4)"; ewhy="$(field "$erow" 5)"
      case "$econd" in
        no-contract) [ "$contract_has" = 0 ] || continue ;;
        unenforced)  [ "$unenforced" = 1 ] || continue ;;
        type=*)      [ "$type" = "${econd#type=}" ] || continue ;;
        *)           continue ;;
      esac
      model="$emodel"; why="$ewhy"
      break
    done <<< "$(conf_rows)"

    printf '%s\t%s\t%s\t%s\n' "$ph" "$agent" "$model" "$why"
  done <<< "$(conf_rows)"
}

# --- which command to drive it with -----------------------------------------

# The next phase after <phase>, read from phases.conf's own order so that a
# phase inserted there does not have to be inserted here as well.
next_phase() {
  awk -F'|' -v cur="$1" '
    !/^#|^[[:space:]]*$/ { gsub(/ /, "", $1)
      if ($1 == "IDLE" || $1 == "SCAFFOLD") next
      order[++n] = $1 }
    END { for (i = 1; i <= n; i++) if (order[i] == cur && i < n) { print order[i+1]; exit } }
  ' "$PHASES"
}

AC_MANY=6   # the crudest signal, and the last one consulted

cmd_next() {
  local file id; id="$1"; file="$(story_file "$id")"
  local type phase acs deferred
  type="$(frontmatter_value "$file" type)"; [ -n "$type" ] || type=feature
  phase="$(frontmatter_value "$file" phase)"; [ -n "$phase" ] || phase=PLANNED

  # A dependency that is not DONE. Recommending either command here sends
  # somebody into a refusal from `phase.sh set`, which is a worse answer than
  # naming the thing they are waiting on.
  local dep blocked=""
  for dep in $(frontmatter_list "$file" depends_on); do
    [ -n "$dep" ] || continue
    local dfile="$STORIES/$dep.md"
    if [ ! -f "$dfile" ]; then blocked="$blocked $dep(missing)"; continue; fi
    [ "$(frontmatter_value "$dfile" phase)" = "DONE" ] || blocked="$blocked $dep"
  done
  if [ -n "$blocked" ]; then
    printf 'blocked\t%s is blocked: depends_on is not DONE —%s. Finish it first, or drop the dependency.\n' \
      "$id" "$blocked"
    return 0
  fi

  if [ "$phase" = "DONE" ]; then
    printf 'none\t%s is DONE. Nothing to drive; start the next story.\n' "$id"
    return 0
  fi

  # Already in flight. The question is not how to run the cycle, it is what the
  # next phase is - and complete-story is never the answer to that.
  if [ "$phase" != "PLANNED" ]; then
    local nxt; nxt="$(next_phase "$phase")"
    printf 'advance-story\t%s is already in %s; advance it to %s. complete-story drives a cycle from the start.\n' \
      "$id" "$phase" "${nxt:-the next phase}"
    return 0
  fi

  # From PLANNED, the question is whether anything in this story wants a human
  # between the phases. Each of these is a reason to stop and look.
  if [ "$type" = "bootstrap" ]; then
    printf 'advance-story\t%s is a bootstrap story: SCAFFOLD writes source, tests and config with no failing test in front of any of it. Drive it a phase at a time.\n' "$id"
    return 0
  fi
  if section "$file" "Deferred verifications" | has_content; then
    printf 'advance-story\t%s carries a Deferred verification, which names a control and the phase that must run it. Something has to stop in that phase and look.\n' "$id"
    return 0
  fi
  acs="$(grep -cE '^[[:space:]]*-[[:space:]]*\*\*AC-' "$file" 2>/dev/null || true)"
  [ -n "$acs" ] || acs=0
  if [ "$acs" -ge "$AC_MANY" ]; then
    printf 'advance-story\t%s has %s acceptance criteria (%s or more). Size is the crudest signal here, but a cycle this wide is worth seeing between phases.\n' \
      "$id" "$acs" "$AC_MANY"
    return 0
  fi

  printf 'complete-story\t%s is an ordinary cycle: a contract to work from, %s criteria, nothing deferred, no dependency waiting. Run it end to end.\n' \
    "$id" "$acs"
}

# --- both, for a human ------------------------------------------------------

cmd_both() {
  local id="$1" nxt cmd why file; file="$(story_file "$id")"
  # Before the pipeline below, not inside it: the scan caches in THIS shell and
  # the subshell inherits it, so cmd_models and the line cost one scan between
  # them rather than two.
  lock_scan "$file"
  nxt="$(cmd_next "$id")"
  cmd="$(printf '%s' "$nxt" | cut -f1)"; why="$(printf '%s' "$nxt" | cut -f2-)"
  printf 'Story %s\n\n' "$id"
  case "$cmd" in
    blocked|none) printf '  %s\n' "$why" ;;
    *)            printf '  Recommended:  /%s %s\n  Because:      %s\n' "$cmd" "$id" "$why" ;;
  esac
  printf '\n  Model plan (from .claude/harness/models.conf — a plan, not a record;\n'
  printf '  write down what each dispatch RESOLVED to, in ## Model guidance):\n\n'
  cmd_models "$id" | while IFS="$(printf '\t')" read -r ph agent model why; do
    printf '    %-9s %-18s %-6s %s\n' "$ph" "$agent" "$model" "$why"
  done
  # Under the plan, where a human reads it, and indented to sit with it. The
  # decision the RED row rests on is otherwise invisible: HARNESS-012's
  # departure had to be reasoned out by hand and written into the story.
  printf '\n    %s\n' "$(lock_coverage_line "$file")"
}

# --- writing the plan into the story ----------------------------------------

# The generated region's fence. `## Model guidance` has three owners, not one:
# this command renders the policy into it, rules.md sends the AUTHOR into it -
# "a story that wants a different answer says so in its own `## Model guidance`
# with a success condition that could come out either way" - and it asks the
# orchestrator to record underneath what each dispatch RESOLVED to. A writer
# that replaced the whole section replaced all three, and that is what this one
# did: NET-001 lost a RED brief and its success condition to a re-run, with
# nothing but `git diff` to say so.
GEN_BEGIN='<!-- plan.sh:generated:begin -->'
GEN_END='<!-- plan.sh:generated:end -->'

# strip_generated   A section body on stdin; what a person wrote on stdout.
#
# Between the markers when they are there. For a section written before they
# existed, the two shapes the old writer emitted: its preamble paragraph, and
# its table. The table is matched on ITS OWN HEADER rather than on a leading
# pipe - an author who tabulates the story's negative controls in this section
# writes table rows too, and a stripper that ate every line starting with `|`
# would delete them while every assertion about prose still passed.
strip_generated() {
  awk -v b="$GEN_BEGIN" -v e="$GEN_END" '
    $0 == b { g = 1; next }
    g { if ($0 == e) g = 0; next }
    index($0, "Planned by `bash scripts/plan.sh write") == 1 { p = 1; next }
    p { if ($0 ~ /^[[:space:]]*$/) p = 0; next }
    index($0, "| Phase | Agent | Planned | Why |") == 1 { t = 1; next }
    t { if (index($0, "|") == 1) next; t = 0 }
    { print }
  ' | awk '
    /^[[:space:]]*$/ { blank = 1; next }
    { if (seen && blank) print ""; seen = 1; blank = 0; print }
  '
}

# Run at the END of PLANNED, once the contract exists. Not at creation: the
# no-contract exception would be baked in before anybody had a chance to write
# one, and a plan that is wrong the moment it is written is worse than none.
#
# It replaces the generated REGION, not the section. The orchestrator re-runs
# this after amending the contract, so a region that grew a copy each time would
# read as a history of decisions nobody made - but everything outside the
# markers belongs to whoever wrote it and is carried through untouched.
cmd_write() {
  local id="$1" file; file="$(story_file "$id")"
  local tmp="$ROOT/.claude/state/plan-write.$$.md"
  mkdir -p "$ROOT/.claude/state"
  # Same scan the rendered rows rest on, taken once here so that the pipeline
  # below and the line beneath the table agree by construction.
  lock_scan "$file"

  # A variable rather than a second scratch file: everything under
  # .claude/state is accounted for in its README, with a column saying whether
  # its contents are read as evidence, and a file that is neither evidence nor
  # worth a row is a file better not created.
  local keep; keep="$(section "$file" "Model guidance" | strip_generated)"

  # Whether the author already has a `**Resolved...` heading, so that re-running
  # does not lay a second one on top of it. `case`, not `grep -q`: a pipe into a
  # command that exits at the first match kills the writer with SIGPIPE, and
  # `pipefail` turns that into a false answer - the defect `has_content` above
  # carries a paragraph about.
  local NL resolved=0; NL=$'\n'
  case "$keep" in '**Resolved'*|*"${NL}**Resolved"*) resolved=1 ;; esac

  {
    printf '## Model guidance\n\n'
    printf '%s\n' "$GEN_BEGIN"
    printf 'Planned by `bash scripts/plan.sh write %s` from `.claude/harness/models.conf`.\n' "$id"
    printf 'A PLAN, not a record: a session setting or an explicit override can beat both\n'
    printf 'this and the agent'"'"'s own `model:` field, and nothing here can see which won.\n'
    printf 'The orchestrator still writes down the model each dispatch **resolved** to, by\n'
    printf 'name, below the table. Only what lies BETWEEN these two markers is rewritten when\n'
    printf 'this command runs again; the rest of the section is yours and is preserved.\n\n'
    printf '| Phase | Agent | Planned | Why |\n|---|---|---|---|\n'
    cmd_models "$id" | while IFS="$(printf '\t')" read -r ph agent model why; do
      printf '| %s | `%s` | `%s` | %s |\n' "$ph" "$agent" "$model" "$why"
    done
    # Beneath the table and INSIDE the region, at column 0. Inside, because
    # strip_generated keeps everything outside the markers and a second write
    # would then leave two copies; beneath, because it is the decision the row
    # above it rests on, and the next agent reads this section, not a terminal.
    printf '\n'
    lock_coverage_line "$file"
    printf '%s\n' "$GEN_END"

    [ -n "$keep" ] && printf '\n%s\n' "$keep"
    if [ "$resolved" = 0 ]; then
      printf '\n**Resolved:**\n\n'
      printf -- '<!-- One line per dispatch, as it happened: phase, agent, the model that\n'
      printf -- '     actually ran, and — if a phase was planned for one model and ran on\n'
      printf -- '     another — what that changed. A choice with no verdict is folklore. -->\n'
    fi
    printf '\n'
  } > "$tmp"

  awk -v planfile="$tmp" '
    /^## Model guidance/ { while ((getline line < planfile) > 0) print line; skip = 1; next }
    skip && /^## / { skip = 0 }
    !skip { print }
  ' "$file" > "$file.new" && mv "$file.new" "$file"
  rm -f "$tmp"

  printf 'wrote the model plan into %s\n' "docs/backlog/stories/$id.md"
  if [ -n "$keep" ]; then
    printf '  kept %s line(s) of existing guidance from outside the generated region\n' \
      "$(grep -c '' <<< "$keep")"
  fi
}

case "${1:-}" in
  models) [ -n "${2:-}" ] || die "usage: plan.sh models <story-id>"; cmd_models "$2" ;;
  write)  [ -n "${2:-}" ] || die "usage: plan.sh write <story-id>";  cmd_write "$2" ;;
  next)   [ -n "${2:-}" ] || die "usage: plan.sh next <story-id>";   cmd_next "$2" ;;
  -h|--help|"") sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)      cmd_both "$1" ;;
esac
