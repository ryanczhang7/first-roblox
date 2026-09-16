#!/usr/bin/env bash
# Tests for scripts/plan.sh - which model each phase of a story runs on, and
# which command to drive it with.
#
# Both answers used to be asked of the human every time, which is the condition
# under which they stop being answers and become habits. The model question in
# particular: `rules.md` has said since WORLD-007 that a model choice with no
# recorded verdict is folklore, and the way a choice becomes folklore is that
# nobody writes down why - so the policy lives in a file with a reason per row,
# and the plan is written INTO the story before the phase it applies to.
#
# The policy is not taste. It is the one measurement this repository has:
#   * a partitioned RED brief on the weaker model produced sharper negative
#     controls than the stronger model without one, so RED runs on the weaker
#     model WHEN THE BRIEF EXISTS, and on the stronger one when it does not;
#   * the failure mode of a weaker model in GREEN or GATES is reaching green by
#     weakening a test, which is precisely what this harness exists to prevent,
#     so those never move.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

FIX="$(make_project_fixture)"
trap 'rm -rf "$FIX"' EXIT

plan() { ( cd "$FIX" && bash scripts/plan.sh "$@" 2>&1 ); }

# story_with <id> <type> <phase> <ac-count> ; section bodies on stdin as
# `SECTION:body` lines, so a case says only what it is about.
story_with() {
  local id="$1" type="$2" phase="$3" acs="$4" extra contract="" deferred="" deps=""
  extra="$(cat)"
  case "$extra" in *CONTRACT:*) contract="$(printf '%s\n' "$extra" | sed -n 's/^CONTRACT://p')" ;; esac
  case "$extra" in *DEFERRED:*) deferred="$(printf '%s\n' "$extra" | sed -n 's/^DEFERRED://p')" ;; esac
  case "$extra" in *DEPENDS:*)  deps="$(printf '%s\n' "$extra" | sed -n 's/^DEPENDS://p')" ;; esac
  mkdir -p "$FIX/docs/backlog/stories"
  {
    printf -- '---\nid: %s\ntitle: Fixture story\nslug: fixture\ntype: %s\nstatus: todo\nphase: %s\nbranch: story/%s-fixture\n' \
      "$id" "$type" "$phase" "$id"
    [ -n "$deps" ] && printf -- 'depends_on: [%s]\n' "$deps"
    printf -- '---\n\n## Acceptance criteria\n\n'
    local i=1
    while [ "$i" -le "$acs" ]; do printf -- '- **AC-%s** - it works.\n' "$i"; i=$((i+1)); done
    printf -- '\n## Contract\n\n'
    [ -n "$contract" ] && printf -- '%s\n' "$contract"
    printf -- '\n## Deferred verifications\n\n'
    [ -n "$deferred" ] && printf -- '%s\n' "$deferred"
    printf -- '\n## Model guidance\n\n## Gate results\n\n## Notes\n'
  } > "$FIX/docs/backlog/stories/$id.md"
}

# A story that is ordinary in every way the rules below care about: a real
# contract, few criteria, nothing deferred, no dependencies.
ordinary() { story_with "${1:-T-1}" "${2:-feature}" "${3:-PLANNED}" 2 <<'EOF'
CONTRACT:`src/core/world.ts` exports `buildWorld(seed: number): World`.
EOF
}

# ---------------------------------------------------------------------------
describe "which model each phase runs on"

ordinary T-1
out="$(plan models T-1)"

# RED is the whole point of the policy, and it is the only row that moves.
assert_contains "RED runs on the weaker model when a brief exists" \
  "RED	test-developer	fable" "$out"

# These two never move, and the reason is the one this harness was built for.
assert_contains "GREEN stays on the stronger model" \
  "GREEN	feature-developer	opus" "$out"
assert_contains "GATES stays on the stronger model" \
  "GATES	feature-developer	opus" "$out"
assert_contains "and the orchestrator does too" \
  "PLANNED	lead-po	opus" "$out"

# Both checks below are loops over the plan's rows, and a loop over nothing
# finds no fault: with no plan at all they reported green while every other
# assertion in this file was red. So the row count is asserted first, and they
# mean something only because it is.
assert_eq "the plan has a row for every dispatching phase" 6 \
  "$(printf '%s\n' "$out" | grep -c '	')"

# A row without a reason is the folklore rules.md warns about, so every row
# carries one and the test refuses a blank.
missing=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  why="$(printf '%s' "$line" | cut -f4-)"
  case "$why" in ''|' ') missing="$missing $(printf '%s' "$line" | cut -f1)" ;; esac
done <<< "$out"
assert_eq "every phase in the plan says why" "" "$missing"

# THE EXCEPTION, and the reason it exists. The measurement was a partitioned
# RED BRIEF against the stronger model without one - so with no contract to
# hand RED, the thing that was measured is not present and the weaker model is
# not what was tested.
story_with T-2 feature PLANNED 2 <<'EOF'
EOF
out="$(plan models T-2)"
assert_contains "with no contract, RED goes back to the stronger model" \
  "RED	test-developer	opus" "$out"
assert_contains "and says it is the brief that is missing" "contract" "$out"

# THE STORY THE LOCK DOES NOT COVER, reported from the field and confirmed
# here: `.claude/tests/*.test.sh`, `scripts/*` and `.claude/hooks/*` all
# classify as `harness`, and `harness` is writable in EVERY phase. So for a
# story that maintains the harness itself, RED may write the mechanism and
# GREEN may rewrite the frozen tests, and nothing complains - the consuming
# project measured `gates.sh --fast` at 13/13 with identical counts across a
# GREEN that added a script, a config file and 25 assertions.
#
# That changes what the RED row is resting on. Elsewhere the contract is an AID
# to the model and the lock is the enforcement; here the contract IS the
# enforcement, the only one there is. A weaker model is a different proposition
# against a safety net than against nothing, so RED stays on the stronger model
# when every path the contract names is one the lock will not freeze.
story_with T-4 feature PLANNED 2 <<'EOF'
CONTRACT:`scripts/plan.sh` gains a `write` subcommand; `.claude/tests/plan.test.sh` pins it.
EOF
out="$(plan models T-4)"
assert_contains "a story the lock cannot police keeps RED on the stronger model" \
  "RED	test-developer	opus" "$out"
assert_contains "and says the lock is what is missing" "lock" "$out"

# THE CONTROL, and the reason this is not just "mentions a script". One source
# path is enough for the lock to bite, and without this assertion the rule
# above would push every story that touches a helper onto the stronger model.
story_with T-5 feature PLANNED 2 <<'EOF'
CONTRACT:`src/core/world.ts` exports `buildWorld`; `scripts/task.sh` gains a `seed` target.
EOF
out="$(plan models T-5)"
assert_contains "but one source path is enough for the lock to bite" \
  "RED	test-developer	fable" "$out"

# A CONTRACT TOO BIG TO READ IS STILL A CONTRACT. `has_content` here was lifted
# from check-boundaries.sh when this script was written, and the defect came with
# it: `strip_comments | grep -q` has an awk that buffers to END feeding a grep
# that exits at the first match, so the writer dies of SIGPIPE and `pipefail`
# turns 141 into "no content". Measured: 50,000 bytes exit 0, 200,000 exit 141.
#
# The consequence here is quieter than a refused PR and worse for it. A thorough
# contract - the kind the RED row exists to reward - reads as ABSENT, the
# no-contract exception fires, and the plan silently moves RED to the stronger
# model. Nothing fails; the story just runs on a model nobody chose, for a reason
# nobody can see.
story_with T-6 feature PLANNED 2 <<'EOF'
CONTRACT:PLACEHOLDER
EOF
{ awk '/^CONTRACT_BODY$/ { exit } { print }' "$FIX/docs/backlog/stories/T-6.md" >/dev/null 2>&1; true; }
big="$(yes '`src/core/world.ts` exports buildWorld(seed: number): World.' | head -c 1572864)"
awk -v body="$big" '
  /^## Contract$/ { print; print ""; print body; skip = 1; next }
  skip && /^## / { skip = 0 }
  !skip { print }
' "$FIX/docs/backlog/stories/T-6.md" > "$FIX/docs/backlog/stories/T-6.md.new" \
  && mv "$FIX/docs/backlog/stories/T-6.md.new" "$FIX/docs/backlog/stories/T-6.md"
out="$(plan models T-6)"
assert_contains "a 1.5 MiB contract still counts as a contract" \
  "RED	test-developer	fable" "$out"

# Bootstrap writes source, tests and config in one indivisible derivation under
# SCAFFOLD, with no failing test to anchor it.
story_with T-3 bootstrap PLANNED 2 <<'EOF'
CONTRACT:the stack, the runner, and the scaffold.
EOF
out="$(plan models T-3)"
assert_contains "a bootstrap story keeps RED on the stronger model" \
  "RED	test-developer	opus" "$out"

# Derived, not listed: every phase that dispatches an agent has a row. A phase
# added to phases.conf with no model row is a phase whose model is decided by
# whatever the session happens to be set to, which is the state this replaces.
unplanned=""
for ph in $(awk -F'|' '!/^#|^[[:space:]]*$/ { gsub(/ /,"",$1); print $1 }' "$FIX/.claude/harness/phases.conf"); do
  case "$ph" in IDLE|DONE) continue ;; esac
  printf '%s\n' "$out" | grep -q "^$ph	" || unplanned="$unplanned $ph"
done
assert_eq "every dispatching phase has a model" "" "$unplanned"

# A model nobody can dispatch is a typo that surfaces as a silent fallback.
bad=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  m="$(printf '%s' "$line" | cut -f3)"
  case "$m" in opus|fable|sonnet|haiku) ;; *) bad="$bad $m" ;; esac
done <<< "$out"
assert_eq "and names a model that can actually be dispatched" "" "$bad"

# ---------------------------------------------------------------------------
describe "which command to drive the story with"

# The ordinary case, and the one the request is about: nothing here needs a
# human between phases.
ordinary T-10
out="$(plan next T-10)"
assert_contains "an ordinary story runs end to end" "complete-story" "$out"
assert_contains "and says why" "T-10" "$out"

# Mid-flight is not a recommendation about the whole cycle; it is the next
# phase, and the answer is never complete-story.
ordinary T-11 feature GREEN
out="$(plan next T-11)"
assert_contains "a story already in flight advances one phase" "advance-story" "$out"
assert_contains "and names the phase it would move to" "GATES" "$out"

# Bootstrap is the one type that writes production code with no failing test
# in front of it. Look between the phases.
story_with T-12 bootstrap PLANNED 2 <<'EOF'
CONTRACT:the stack and the runner.
EOF
out="$(plan next T-12)"
assert_contains "a bootstrap story is driven one phase at a time" "advance-story" "$out"

# A deferred verification names a control and the phase that must run it, so
# something has to stop in that phase and look.
story_with T-13 feature PLANNED 2 <<'EOF'
CONTRACT:`src/core/world.ts` exports `buildWorld`.
DEFERRED:- AC-2's negative control cannot run until the renderer exists. Owner: GREEN
EOF
out="$(plan next T-13)"
assert_contains "so is one carrying a deferred verification" "advance-story" "$out"
assert_contains "and the reason names it" "Deferred" "$out"

# Size is the crudest signal and the last one consulted, which is why it is a
# threshold rather than a judgement.
story_with T-14 feature PLANNED 9 <<'EOF'
CONTRACT:`src/core/world.ts` exports `buildWorld`.
EOF
out="$(plan next T-14)"
assert_contains "and one with many criteria" "advance-story" "$out"

# A story whose dependency is not DONE cannot be driven by either command, and
# saying `complete-story` here sends somebody into a refusal from phase.sh.
ordinary T-20 feature DONE
story_with T-21 feature PLANNED 2 <<'EOF'
CONTRACT:`src/core/world.ts` exports `buildWorld`.
DEPENDS:T-22
EOF
story_with T-22 feature GREEN 2 <<'EOF'
CONTRACT:something else.
EOF
out="$(plan next T-21)"
assert_contains "a blocked story recommends neither" "blocked" "$out"
assert_contains "and names the dependency that blocks it" "T-22" "$out"

# The same story once its dependency lands.
story_with T-22 feature DONE 2 <<'EOF'
CONTRACT:something else.
EOF
out="$(plan next T-21)"
assert_contains "and stops being blocked when the dependency is DONE" "complete-story" "$out"

# DONE is not a recommendation to do anything.
ordinary T-30 feature DONE
out="$(plan next T-30)"
case "$out" in
  *advance-story*|*complete-story*) _bad "a DONE story recommends no command" "it recommended one: $out" ;;
  *) _ok "a DONE story recommends no command" ;;
esac

# ---------------------------------------------------------------------------
describe "the plan is written into the story, not left to be looked up"

# `## Gate results` is written by gates.sh and never by hand, for a reason that
# applies here too: a section a person retypes is a section that drifts from
# what the tool would say. The plan goes in at the END of PLANNED, because it
# depends on the contract - writing it at creation time would bake in the
# no-contract exception before anybody had a chance to write one.
ordinary T-40
plan write T-40 >/dev/null
body="$(awk '/^## Model guidance/{on=1;next} on&&/^## /{exit} on{print}' "$FIX/docs/backlog/stories/T-40.md")"
assert_contains "the section carries the plan" "RED" "$body"
assert_contains "with the model for each phase" "fable" "$body"
assert_contains "and the reason, not just the name" "negative controls" "$body"
# It is a PLAN. rules.md wants the resolved model recorded, and a section that
# looked like a record would quietly satisfy a rule it does not satisfy.
assert_contains "and says it is a plan, not a record" "resolved" "$body"

# Nothing else in the story moves.
assert_contains "the criteria are untouched" "**AC-1**" "$(cat "$FIX/docs/backlog/stories/T-40.md")"
assert_contains "and so is the contract" "buildWorld" "$(cat "$FIX/docs/backlog/stories/T-40.md")"

# Writing twice is writing once: the orchestrator re-runs this after amending
# the contract, and a section that grew a second copy each time would be worse
# than no section.
plan write T-40 >/dev/null
assert_eq "writing it again replaces rather than appends" 1 \
  "$(grep -c '^| RED ' "$FIX/docs/backlog/stories/T-40.md")"

summary "plan"
