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
contract_unenforced() { # <file>
  local paths p found=0 enforced=0
  paths="$(section "$1" "Contract" | strip_comments \
    | grep -oE '\.claude/[A-Za-z0-9_./-]+|[A-Za-z0-9_][A-Za-z0-9_./-]*\.[A-Za-z0-9]+' | sort -u)"
  [ -n "$paths" ] || return 1
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    found=1
    case "$(classify "$p")" in
      harness|docs|ignored) ;;
      *) enforced=1 ;;
    esac
  done <<< "$paths"
  [ "$found" = 1 ] && [ "$enforced" = 0 ]
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
  local id="$1" nxt cmd why
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
}

# --- writing the plan into the story ----------------------------------------

# Run at the END of PLANNED, once the contract exists. Not at creation: the
# no-contract exception would be baked in before anybody had a chance to write
# one, and a plan that is wrong the moment it is written is worse than none.
#
# It replaces the section rather than appending to it, because the orchestrator
# re-runs this after amending the contract and a section that grew a copy each
# time would be read as a history of decisions nobody made.
cmd_write() {
  local id="$1" file; file="$(story_file "$id")"
  local tmp="$ROOT/.claude/state/plan-write.$$.md"
  mkdir -p "$ROOT/.claude/state"

  {
    printf '## Model guidance\n\n'
    printf 'Planned by `bash scripts/plan.sh write %s` from `.claude/harness/models.conf`.\n' "$id"
    printf 'A PLAN, not a record: a session setting or an explicit override can beat both\n'
    printf 'this and the agent'"'"'s own `model:` field, and nothing here can see which won.\n'
    printf 'The orchestrator still writes down the model each dispatch **resolved** to, by\n'
    printf 'name, below the table.\n\n'
    printf '| Phase | Agent | Planned | Why |\n|---|---|---|---|\n'
    cmd_models "$id" | while IFS="$(printf '\t')" read -r ph agent model why; do
      printf '| %s | `%s` | `%s` | %s |\n' "$ph" "$agent" "$model" "$why"
    done
    printf '\n**Resolved:**\n\n'
    printf -- '<!-- One line per dispatch, as it happened: phase, agent, the model that\n'
    printf -- '     actually ran, and — if a phase was planned for one model and ran on\n'
    printf -- '     another — what that changed. A choice with no verdict is folklore. -->\n'
  } > "$tmp"

  awk -v planfile="$tmp" '
    /^## Model guidance/ { while ((getline line < planfile) > 0) print line; skip = 1; next }
    skip && /^## / { skip = 0 }
    !skip { print }
  ' "$file" > "$file.new" && mv "$file.new" "$file"
  rm -f "$tmp"
  printf 'wrote the model plan into %s\n' "docs/backlog/stories/$id.md"
}

case "${1:-}" in
  models) [ -n "${2:-}" ] || die "usage: plan.sh models <story-id>"; cmd_models "$2" ;;
  write)  [ -n "${2:-}" ] || die "usage: plan.sh write <story-id>";  cmd_write "$2" ;;
  next)   [ -n "${2:-}" ] || die "usage: plan.sh next <story-id>";   cmd_next "$2" ;;
  -h|--help|"") sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)      cmd_both "$1" ;;
esac
