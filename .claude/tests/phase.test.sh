#!/usr/bin/env bash
# Tests for scripts/phase.sh and the story frontmatter readers in lib.sh.
#
# phase.sh is the only supported way to change phase, so the checks it makes -
# unmet dependencies, the wrong branch - are load-bearing: an agent that gets
# past them starts writing code under a lock that says something untrue.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

FIX="$(make_project_fixture)"
trap 'rm -rf "$FIX"' EXIT

export CLAUDE_PROJECT_DIR="$FIX"
. "$REPO_ROOT/.claude/hooks/lib.sh"

phase() { ( cd "$FIX" && bash scripts/phase.sh "$@" 2>&1 ); }
new_story() { ( cd "$FIX" && bash scripts/new-story.sh "$@" 2>&1 ); }
sfile() { printf '%s/docs/backlog/stories/%s.md' "$FIX" "$1"; }

# ---------------------------------------------------------------------------
describe "frontmatter readers"

story "$FIX" T-9 PLANNED <<'EOF'
depends_on: [T-7, T-8]
required_gates: [integration]
EOF

assert_eq "a scalar"            "T-9"       "$(frontmatter_value "$(sfile T-9)" id)"
assert_eq "a phase"             "PLANNED"   "$(frontmatter_value "$(sfile T-9)" phase)"
assert_eq "an inline list"      "T-7 T-8 "  "$(frontmatter_list "$(sfile T-9)" depends_on | tr '\n' ' ')"
assert_eq "a one-element list"  "integration " "$(frontmatter_list "$(sfile T-9)" required_gates | tr '\n' ' ')"
assert_eq "a key that is absent" ""         "$(frontmatter_list "$(sfile T-9)" nope)"

# The block form, which YAML allows and an agent may well write by hand.
cat > "$(sfile T-10)" <<'EOF'
---
id: T-10
title: Block form
type: feature
status: todo
phase: PLANNED
depends_on:
  - T-7
  - T-8
---

## Acceptance criteria
EOF
assert_eq "a block list" "T-7 T-8 " "$(frontmatter_list "$(sfile T-10)" depends_on | tr '\n' ' ')"

# ---------------------------------------------------------------------------
describe "new-story.sh writes a story the harness can read"

out="$(new_story T-11 "A hex grid renders" EPIC-1 feature)"
assert_contains "it says where it went" "docs/backlog/stories/T-11.md" "$out"
assert_eq "id"       "T-11"                    "$(frontmatter_value "$(sfile T-11)" id)"
assert_eq "phase"    "PLANNED"                 "$(frontmatter_value "$(sfile T-11)" phase)"
assert_eq "branch"   "story/T-11-a-hex-grid-renders" "$(frontmatter_value "$(sfile T-11)" branch)"
assert_eq "required_gates starts empty" "" "$(frontmatter_list "$(sfile T-11)" required_gates | tr -d ' ')"

# ---------------------------------------------------------------------------
describe "phase.sh set: the branch has to match"

out="$(phase set T-11 RED)"
assert_contains "it refuses on the wrong branch" "belongs on" "$out"
assert_eq "and the story did not move" "PLANNED" "$(frontmatter_value "$(sfile T-11)" phase)"

git -C "$FIX" checkout -q -b story/T-11-a-hex-grid-renders
out="$(phase set T-11 RED)"
assert_contains "on the right branch it moves" "T-11 -> RED" "$out"

# A phase name that merely regex-matches a row is not a phase. `GREEN.` was
# accepted, written to the state file, and phase_allows - finding no such row
# - fell back to "unknown phase, do not block": the lock off, by typo.
out="$(phase set T-11 'GREEN.')"
assert_contains "a regex-matching phase name is refused" "unknown phase" "$out"
assert_eq "and the story did not move" "RED" "$(frontmatter_value "$(sfile T-11)" phase)"
assert_eq "frontmatter phase"  "RED"         "$(frontmatter_value "$(sfile T-11)" phase)"
assert_eq "frontmatter status" "in-progress" "$(frontmatter_value "$(sfile T-11)" status)"
assert_contains "and the hooks can see it" "PHASE=RED" "$(cat "$FIX/.claude/state/current-story.env")"

# `GREEN.` is KEPT, and it is also not the input that discriminates. As an awk
# regex it requires a sixth character, so it fails to match the row `GREEN`
# under `~` exactly as it does under `==` - the control for the defect cannot
# tell the fixed implementation from the broken one. A test named for the
# property it checks, using an input that cannot fail, is what this replaces.
#
# The inputs that DO discriminate are the ones where the typo is a prefix or a
# substring of a real phase. `cmd_set` uppercases its argument, so a fat-fingered
# `gree` arrives here as `GREE`.
for bad in GREE RE D; do
  out="$(phase set T-11 "$bad")"
  assert_contains "a phase name that is a prefix of a real one is refused: $bad" "unknown phase" "$out"
done
# And the metacharacter that matches every row at once.
out="$(phase set T-11 '.')"
assert_contains "so is a regex metacharacter matching any row" "unknown phase" "$out"

# Refusing is only half of it: nothing may have moved. A refusal that had
# already written the state file would leave the guard reading a phase the
# story does not claim.
assert_eq "and after all of them the story is still RED" "RED" "$(frontmatter_value "$(sfile T-11)" phase)"
assert_contains "and so is the state the hooks read" "PHASE=RED" "$(cat "$FIX/.claude/state/current-story.env")"

# --- the branch frontmatter, which is what check-boundaries reads ------------
#
# `check-boundaries.sh` finds the story that CLAIMS a branch by reading this
# key; with no claimant it skips eight checks and says so. new-story.sh writes
# it too, so on the common path this write is redundant - it is load-bearing for
# a story file written or edited by hand, and for one whose branch changed,
# which is exactly the file this fixture builds.
git -C "$FIX" checkout -q -b story/T-12-nobranch 2>/dev/null
mkdir -p "$FIX/docs/backlog/stories"
{
  printf -- '---\nid: T-12\ntitle: No branch key\nslug: nobranch\ntype: feature\nstatus: todo\nphase: PLANNED\n---\n\n'
  printf -- '## Acceptance criteria\n\n- **AC-1** - it works.\n'
} > "$FIX/docs/backlog/stories/T-12.md"
out="$(phase set T-12 RED)"
assert_contains "a story file with no branch: key still moves" "T-12 -> RED" "$out"
fm_branch="$(frontmatter_value "$FIX/docs/backlog/stories/T-12.md" branch)"
state_branch="$(sed -nE 's/^BRANCH=//p' "$FIX/.claude/state/current-story.env" | head -1)"
assert_eq "and the branch key is written into the frontmatter" "story/T-12-nobranch" "$fm_branch"
assert_eq "matching the branch the hooks were told about" "$state_branch" "$fm_branch"

# ---------------------------------------------------------------------------
describe "phase.sh set: dependencies have to be DONE"

story "$FIX" T-12 PLANNED <<'EOF'
depends_on: [T-11]
EOF
git -C "$FIX" checkout -q -b story/T-12-fixture
out="$(phase set T-12 RED)"
assert_contains "it refuses"        "depends on stories that are not DONE" "$out"
assert_contains "and names the one" "T-11" "$out"

out="$(phase set T-12 RED --force)"
assert_contains "--force says what it overrode" "warning: --force overrides unmet dependencies" "$out"
assert_eq "and moves the story" "RED" "$(frontmatter_value "$(sfile T-12)" phase)"

phase set T-11 DONE >/dev/null
git -C "$FIX" checkout -q story/T-12-fixture
out="$(phase set T-12 GREEN)"
assert_contains "with the dependency DONE it just moves" "T-12 -> GREEN" "$out"

phase clear >/dev/null

summary "phase"
