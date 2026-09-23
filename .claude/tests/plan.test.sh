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

# THE DECLARATION, and why the scan behind the two cases above is not the whole
# answer (HARNESS-014). The scan asks "does the Contract MENTION a path the lock
# freezes?" when the question it stands in for is "does this story WRITE one?",
# and the two differ for every story whose contract names a fixture, a tool's
# output or a measurement. HARNESS-012 - both of whose files are `harness` -
# was scanned into sixteen tokens of which five classified as `source`:
# `src/main.ts` (a fixture inside a throwaway repository), `5.3.15` (a bash
# version out of a measurement note), `i.e` (English), and the bare filenames
# `classify.sh` and `mutate.sh`. Measured by the Lead PO at PLANNED; read out
# here, not re-derived. The exception fell silently on the WEAK side, for
# exactly the story it was written for.
#
# So when the Contract carries a `### Files` table, the decision is made from
# that table's first column and from nothing else in the section. T-7 is
# HARNESS-012's Contract in miniature, the four non-path tokens included: they
# are the reproduction, not decoration. Note the header row - this repository's
# convention puts `classify.sh` in its second column, so an implementation that
# scans the whole table rather than its first column reproduces the bug it is
# fixing.
#
# Captured from stdout ALONE, not `plan` (which merges stderr): the same capture
# is measured for its shape further down, and the three parsers that shape
# protects read only stdout.
models_stdout() { ( cd "$FIX" && bash scripts/plan.sh models "$1" 2>/dev/null ); }

# red_row <needle-after-RED> <out>   How many rows are `RED<TAB>test-developer
# <TAB><model><TAB><why...>`, anchored at the line start and counted. `opus` on
# its own would not say WHICH exception fired - `no-contract` renders the same
# model - so where the point is that the lock is what is missing, the needle
# runs on into the `unenforced` row's own reason.
red_row() { printf '%s\n' "$2" | grep -c "^RED	test-developer	$1"; }

story_with T-7 fix PLANNED 2 <<'EOF'
CONTRACT:### Files
CONTRACT:
CONTRACT:| Path | `classify.sh` says | Who writes it |
CONTRACT:|---|---|---|
CONTRACT:| `scripts/mutate.sh` | `harness` | GREEN |
CONTRACT:| `.claude/tests/mutate.test.sh` | `harness` | RED |
CONTRACT:
CONTRACT:### Measurement
CONTRACT:
CONTRACT:The fixture writes `src/main.ts` inside a throwaway repository; measured under
CONTRACT:`bash 5.3.15(2)`, i.e. the shell the runner ships, and put through classify.sh once.
EOF
decl_harness="$(models_stdout T-7)"
assert_eq "a story that DECLARES only harness paths keeps RED on the stronger model, whatever its prose mentions" 1 \
  "$(red_row "opus	the lock freezes none of the paths" "$decl_harness")"

# THE CONTROL on the declaration, and the reason the fix is not "ignore declared
# paths": one declared path the lock freezes is still enough for it to bite.
story_with T-8 fix PLANNED 2 <<'EOF'
CONTRACT:### Files
CONTRACT:
CONTRACT:| Path | `classify.sh` says | Who writes it |
CONTRACT:|---|---|---|
CONTRACT:| `src/core/world.ts` | `source` | GREEN |
CONTRACT:| `scripts/task.sh` | `harness` | GREEN |
CONTRACT:
CONTRACT:The world builder gains a seed argument and the task runner a target for it.
EOF
decl_source="$(models_stdout T-8)"
assert_eq "but one DECLARED source path is enough for the lock to bite" 1 \
  "$(red_row "fable	" "$decl_source")"

# THE FALLBACK'S THIRD ROW. T-4 and T-5 above are the first two: with no table,
# the decision is the whole-section scan, byte for byte. A contract that names
# no paths at all does not trigger the exception - there is nothing for the
# lock to have declined to freeze - and it is not the no-contract case either,
# because there IS a contract.
story_with T-9 fix PLANNED 2 <<'EOF'
CONTRACT:The runner learns a seed target and the world builder honours it; nothing else moves.
EOF
nopaths="$(models_stdout T-9)"
assert_eq "a contract naming no paths at all follows the plain plan" 1 \
  "$(red_row "fable	" "$nopaths")"

# THE SHAPE OF THE STREAM, on every verdict the decision can reach. Three
# callers parse `plan models` field-wise and would swallow a stray line without
# complaining: cmd_both and cmd_write both `while IFS=$'\t' read -r ph agent
# model why`, and phase.sh runs `awk -F'\t' '$1 == p { print $3 }'`. A note
# leaking into this stream is a junk row in every rendered table and a blank
# model in `phase.sh show`. The row count near the top of this file counts
# lines CONTAINING A TAB, and a leaked note carries none - so it is blind to
# exactly this, and the count here is of ALL lines. This is the negative
# control on the human-readable line asserted further down.
assert_tsv_shape() { # <what> <stdout>
  assert_eq "$1: stdout is exactly six lines" 6 "$(printf '%s\n' "$2" | grep -c '')"
  assert_eq "$1: and every one of them is PHASE<TAB>agent<TAB>model<TAB>why" 0 \
    "$(printf '%s\n' "$2" | awk -F'\t' 'NF != 4 || $1 == "" || $2 == "" || $3 == "" || $4 == "" { n++ } END { print n + 0 }')"
}
assert_tsv_shape "when the exception applies" "$decl_harness"
assert_tsv_shape "when it is suppressed"      "$decl_source"
assert_tsv_shape "when it is not considered"  "$nopaths"

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
#
# The body is STREAMED into the file rather than held in a shell variable and
# passed through `awk -v`: a megabyte on a command line stalls indefinitely here,
# which is a fact about this fixture rather than about the defect.
{
  printf -- '---\nid: T-6\ntitle: Fixture story\nslug: fixture\ntype: feature\nstatus: todo\nphase: PLANNED\nbranch: story/T-6-fixture\n---\n\n'
  printf -- '## Acceptance criteria\n\n- **AC-1** - it works.\n\n## Contract\n\n'
  yes '`src/core/world.ts` exports buildWorld(seed: number): World.' | head -c 1572864
  printf -- '\n\n## Deferred verifications\n\n## Model guidance\n\n## Gate results\n\n## Notes\n'
} > "$FIX/docs/backlog/stories/T-6.md"
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

# ---------------------------------------------------------------------------
describe "a write preserves the story's own guidance"

# `## Model guidance` is not a generated section with a generated section's
# rules. rules.md sends authors INTO it: "A story that wants a different answer
# says so in its own `## Model guidance` with a success condition that could
# come out either way - it does not edit the policy file." It also asks the
# orchestrator to record, under the table, what each dispatch RESOLVED to.
#
# So the section holds two things with different owners, and `plan write`
# replaced the whole of it with the rendered policy - deleting the brief and the
# success condition the rules had just told the author to put there, and the
# resolved record with them. Reproduced against NET-001 on 2026-09-21: a RED
# brief and a `**Success condition:**` line went in, `plan write` ran, and
# `git diff` showed both gone.
#
# The generated region is now fenced by markers. Everything outside them in that
# section belongs to whoever wrote it and survives the rewrite.

# guidance <id>   The body of the story's `## Model guidance` section.
guidance() {
  awk '/^## Model guidance/{on=1;next} on&&/^## /{exit} on{print}' \
    "$FIX/docs/backlog/stories/$1.md"
}

# put_guidance <id>   Body on stdin, placed under that heading.
put_guidance() {
  local f="$FIX/docs/backlog/stories/$1.md" body; body="$(cat)"
  awk -v body="$body" '/^## Model guidance/ { print; print ""; print body; next } { print }' \
    "$f" > "$f.new" && mv "$f.new" "$f"
}

ordinary T-50
put_guidance T-50 <<'EOF'
Brief RED that this is the adversarial story of the backlog: the valuable test
is not that a valid call is accepted but that four wrong ones are refused.

**Success condition:** the AC-5 control fails against a plausible wrong
implementation, demonstrated in the handoff rather than described.
EOF
plan write T-50 >/dev/null
body="$(guidance T-50)"
assert_contains "the story's own brief survives the write" \
  "adversarial story of the backlog" "$body"
assert_contains "and the success condition rules.md asks for with it" \
  "**Success condition:**" "$body"
# The preservation is worth nothing if it cost the thing being preserved around.
assert_contains "while the rendered plan is still written" "| RED |" "$body"
assert_contains "with the model for each phase" "fable" "$body"

# Re-running is the case that produced the loss: the orchestrator runs this
# again after amending the contract. Replacing the generated region must not
# mean replacing the section, and must not mean a second copy of either half.
plan write T-50 >/dev/null
assert_eq "writing again does not duplicate the preserved prose" 1 \
  "$(grep -c 'adversarial story of the backlog' "$FIX/docs/backlog/stories/T-50.md")"
assert_eq "nor the success condition" 1 \
  "$(grep -c 'Success condition' "$FIX/docs/backlog/stories/T-50.md")"
assert_eq "nor the plan table" 1 \
  "$(grep -c '^| RED ' "$FIX/docs/backlog/stories/T-50.md")"

# A section written by the OLD writer has no markers, and stale policy rows in
# it are genuinely generated content - they must go, or the story ends up
# carrying two answers to the same question. Everything around them stays.
ordinary T-51
put_guidance T-51 <<'EOF'
Planned by `bash scripts/plan.sh write T-51` from `.claude/harness/models.conf`.
A PLAN, not a record: a session setting or an explicit override can beat both
this and the agent's own `model:` field, and nothing here can see which won.

| Phase | Agent | Planned | Why |
|---|---|---|---|
| RED | `test-developer` | `sonnet` | a stale row from an earlier run |

**Resolved:**

RED dispatched and resolved to fable.

This story argues for something different, and here is the argument.
EOF
plan write T-51 >/dev/null
body="$(guidance T-51)"
assert_contains "an unmarked section's prose survives too" \
  "argues for something different" "$body"
assert_contains "and the resolved record, which is not a plan" \
  "RED dispatched and resolved to fable." "$body"
assert_eq "while the stale policy row is replaced rather than kept" 0 \
  "$(grep -c 'a stale row from an earlier run' "$FIX/docs/backlog/stories/T-51.md")"
assert_eq "leaving exactly one row per phase" 1 \
  "$(grep -c '^| RED ' "$FIX/docs/backlog/stories/T-51.md")"

# THE CONTROL for the rule above, and the reason it keys on the plan table's own
# header rather than on a leading pipe. An author who tabulates their negative
# controls in this section writes markdown table rows too, and a stripper that
# ate every line starting with `|` would delete them and pass every assertion
# above.
ordinary T-52
put_guidance T-52 <<'EOF'
The controls this story turns on, and what each is expected to report:

| Control | Expected |
|---|---|
| a call from a player who is not seated | rejected |
EOF
plan write T-52 >/dev/null
body="$(guidance T-52)"
assert_contains "a table the author wrote is not the generated one" \
  "a call from a player who is not seated" "$body"
assert_contains "and its header survives as well" "| Control | Expected |" "$body"

# Nothing outside the section moves, on any of these.
assert_contains "the criteria are untouched" "**AC-1**" \
  "$(cat "$FIX/docs/backlog/stories/T-51.md")"
assert_contains "and so is the contract" "buildWorld" \
  "$(cat "$FIX/docs/backlog/stories/T-51.md")"

# ---------------------------------------------------------------------------
describe "the lock-coverage decision is said out loud"

# HARNESS-014's other half. The `unenforced` decision was invisible: nothing in
# plan.sh's output said whether the exception was considered, applied or
# suppressed, or by what - so a wrong verdict had to be found by reading the
# source, and HARNESS-012's departure was written into `## Model guidance` by
# hand. The fallback scan is still allowed to be wrong (narrowing its regex is
# out of scope), and what makes that safe is that it now SAYS what it decided:
# a story whose prose mentions `i.e.` reads "SUPPRESSED by `i.e` (source)",
# which is the cheapest possible signal that the heuristic misfired.
#
# One line, three verdicts, and the keywords are mutually non-matching
# substrings on purpose. rules.md carries four real cases of a needle that
# could not fail, one satisfied by the string meaning the opposite - so every
# assertion here is ANCHORED at the line start and COUNTED, never a floating
# `assert_contains` on a multi-paragraph output, where the word SUPPRESSED
# somewhere is no evidence the line was emitted once, in the right place, about
# the right path.
APPLIES='^[[:space:]]*Lock coverage: APPLIES'
SUPPRESSED='^[[:space:]]*Lock coverage: SUPPRESSED by '
NOT_CONSIDERED='^[[:space:]]*Lock coverage: NOT CONSIDERED'
ANY_VERDICT='^[[:space:]]*Lock coverage: '
DECLARED="declared in the Contract's ### Files table"
SCANNED='scanned from the Contract text'
lines_matching() { printf '%s\n' "$2" | grep -cE "$1"; }

# THE INSTRUMENT, checked before it is pointed at anything. The three verdict
# needles against the three verbatim forms from the story's Contract, plus a
# fourth line that means the opposite of one of them: each needle must count 1
# on its own line and 0 on every other. This is the demonstration the story
# asks for - not a claim that the keywords differ, but the matrix.
verdict_matrix=""
while IFS= read -r line; do
  verdict_matrix="$verdict_matrix$(lines_matching "$APPLIES" "$line")$(lines_matching "$SUPPRESSED" "$line")$(lines_matching "$NOT_CONSIDERED" "$line") "
done <<'EOF'
Lock coverage: APPLIES — all 2 path(s) declared in the Contract's ### Files table are harness/docs/ignored, so RED stays on the stronger model.
Lock coverage: SUPPRESSED by `src/core/world.ts` (source), scanned from the Contract text — the phase lock freezes it, so RED follows the plain plan.
Lock coverage: NOT CONSIDERED — this contract names no paths.
    Lock coverage: NOT SUPPRESSED by anything — the opposite of a verdict, which an unanchored needle would accept.
EOF
assert_eq "no verdict needle matches another verdict's line, nor its own negation" \
  "100 010 001 000 " "$verdict_matrix"

# F-DECL-HARNESS (T-7): the paths were DECLARED, and the exception applied.
both="$(plan T-7)"
assert_eq "F-DECL-HARNESS: the human plan carries exactly one lock-coverage line" 1 \
  "$(lines_matching "$ANY_VERDICT" "$both")"
assert_eq "and it says the exception APPLIES" 1 "$(lines_matching "$APPLIES" "$both")"
assert_eq "to all 2 paths declared in the ### Files table, not scanned from the text" 1 \
  "$(lines_matching "$APPLIES.*all 2 path[(]s[)] $DECLARED" "$both")"
assert_eq "not SUPPRESSED" 0 "$(lines_matching "$SUPPRESSED" "$both")"
assert_eq "not NOT CONSIDERED" 0 "$(lines_matching "$NOT_CONSIDERED" "$both")"

# F-NODECL-SOURCE (T-5): no table, so the text was SCANNED, and one source path
# suppressed it. The line has to name that path and the category classify.sh
# gave it - the whole point is that a bad fallback verdict shows its working.
both="$(plan T-5)"
assert_eq "F-NODECL-SOURCE: exactly one lock-coverage line" 1 \
  "$(lines_matching "$ANY_VERDICT" "$both")"
assert_eq "and it says the exception was SUPPRESSED" 1 "$(lines_matching "$SUPPRESSED" "$both")"
assert_eq "by the source path, with the category classify.sh gave it" 1 \
  "$(lines_matching "$SUPPRESSED"'.*`src/core/world.ts` [(]source[)]' "$both")"
assert_eq "and says the paths were scanned from the text, there being no table" 1 \
  "$(lines_matching "$SUPPRESSED.*$SCANNED" "$both")"
assert_eq "not APPLIES" 0 "$(lines_matching "$APPLIES" "$both")"
assert_eq "not NOT CONSIDERED" 0 "$(lines_matching "$NOT_CONSIDERED" "$both")"

# F-NOPATHS (T-9): a contract, but nothing in it for the lock to decline.
both="$(plan T-9)"
assert_eq "F-NOPATHS: exactly one lock-coverage line" 1 \
  "$(lines_matching "$ANY_VERDICT" "$both")"
assert_eq "and it says the exception was NOT CONSIDERED" 1 \
  "$(lines_matching "$NOT_CONSIDERED" "$both")"
assert_eq "not APPLIES" 0 "$(lines_matching "$APPLIES" "$both")"
assert_eq "not SUPPRESSED" 0 "$(lines_matching "$SUPPRESSED" "$both")"

# F-DECL-SOURCE (T-8): the visible half of the AC-2 control. A DECLARED source
# path suppresses the exception and the line says so, naming the table as its
# source - which is what separates "read what the story declares" from "assume
# a story with a table is harness-only".
both="$(plan T-8)"
assert_eq "F-DECL-SOURCE: exactly one lock-coverage line" 1 \
  "$(lines_matching "$ANY_VERDICT" "$both")"
assert_eq "SUPPRESSED by the declared source path, and the paths came from the table" 1 \
  "$(lines_matching "$SUPPRESSED"'.*`src/core/world.ts` [(]source[)].*'"$DECLARED" "$both")"
assert_eq "not APPLIES" 0 "$(lines_matching "$APPLIES" "$both")"

# ---------------------------------------------------------------------------
describe "and written into the story with the plan"

# Where it has to land. HARNESS-012's departure was written by hand into
# `## Model guidance` because nothing put it there; the next agent reads that
# section, not a terminal. Inside the generated region, beneath the table, so
# that a re-run replaces it rather than stacking a copy - and counted in THAT
# slice, not in the whole file, because a line written outside the markers
# would survive `strip_generated` and be duplicated by the second write.
GEN_BEGIN='<!-- plan.sh:generated:begin -->'
GEN_END='<!-- plan.sh:generated:end -->'

# generated <id>   What lies between the markers in the story's `## Model
# guidance`, and nothing outside them.
generated() {
  awk -v b="$GEN_BEGIN" -v e="$GEN_END" '$0 == e { exit } g { print } $0 == b { g = 1 }' \
    "$FIX/docs/backlog/stories/$1.md"
}

put_guidance T-7 <<'EOF'
Brief RED that both files here are `harness`: the lock will permit the write the
law forbids, so the contract is the only enforcement there is.
EOF
plan write T-7 >/dev/null
region="$(generated T-7)"
assert_eq "the generated region carries the lock-coverage line, once" 1 \
  "$(lines_matching "$ANY_VERDICT" "$region")"
assert_eq "and it is the same verdict the human plan gave" 1 \
  "$(lines_matching "$APPLIES.*all 2 path[(]s[)] $DECLARED" "$region")"
assert_eq "at column 0, beneath the table" after \
  "$(printf '%s\n' "$region" | awk '/^\|/ { t = NR } /^Lock coverage: / { l = NR } END { print (l && l > t) ? "after" : "not-after" }')"
assert_eq "and nowhere else in the story file" 1 \
  "$(grep -cE "$ANY_VERDICT" "$FIX/docs/backlog/stories/T-7.md")"

# Writing twice is writing once, for the line as for the table.
plan write T-7 >/dev/null
assert_eq "writing again leaves exactly one copy in the file" 1 \
  "$(grep -cE "$ANY_VERDICT" "$FIX/docs/backlog/stories/T-7.md")"
assert_eq "still inside the generated region" 1 \
  "$(lines_matching "$ANY_VERDICT" "$(generated T-7)")"
assert_eq "and the brief outside the markers is untouched" 1 \
  "$(grep -c 'the contract is the only enforcement there is' "$FIX/docs/backlog/stories/T-7.md")"

summary "plan"
