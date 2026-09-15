#!/usr/bin/env bash
# Tests for scripts/ci-local.sh - the local run of what CI runs.
#
# The script's whole value is that it is the SAME sequence, and that is exactly
# the property that rots: somebody adds a step to gates.yml, nobody adds it here,
# and a green local run starts meaning less than it says. So the load-bearing
# test is not "does it work" - it is "does it still agree with the workflows",
# derived from the workflow files rather than from a list copied out of them.
#
# The other half is fail-fast. A runner stops a job at the first failing step;
# a script that carries on and prints a summary at the end can report four
# passes under a failure, which is the one thing a CI substitute must not do.

. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

SCRIPT="$REPO_ROOT/scripts/ci-local.sh"
WF="$REPO_ROOT/.github/workflows"

# ---------------------------------------------------------------------------
describe "it runs what the workflows run"

# --dry-run prints the commands and executes none of them, which is what makes
# this checkable at all: the alternative is running the real suite to find out
# what it would have run.
dry="$( bash "$SCRIPT" --dry-run 2>&1 )"
assert_eq "--dry-run succeeds" 0 "$?"


# The script must RUN what the workflows say, and the only way to guarantee that
# in a project whose workflows this repository does not control is to read them.
#
# The first version hardcoded five steps and this test asserted they matched the
# workflow files. In THIS repository they matched by construction, so the test
# passed and looked meaningful. In a consuming project the workflow legitimately
# gains `pnpm install --frozen-lockfile` and `pnpm exec playwright install`, and
# the assertion then failed permanently, in a suite nobody could make green - the
# precise shape of red that teaches people to stop reading test output.
#
# So: derive. These assert the derivation, not a list.
missing=""
while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  case "$cmd" in *'${{'*) continue ;; esac
  printf '%s\n' "$dry" | grep -qF -- "$cmd" || missing="$missing
  $cmd"
done <<< "$(grep -hE '^[[:space:]]*run:' "$WF"/gates.yml "$WF"/boundaries.yml \
             | sed -E 's/^[[:space:]]*run:[[:space:]]*//')"
assert_eq "every workflow step appears in the script" "" "$missing"

# ---------------------------------------------------------------------------
describe "a project whose workflow has its own steps"

# The regression. A consuming project adds toolchain setup to gates.yml; those
# steps ARE part of what CI runs, so a local stand-in that skips them is not a
# stand-in. Nothing here may be specific to this repository's own five commands.
PFIX="$(make_project_fixture)"
mkdir -p "$PFIX/.github/workflows"
cat > "$PFIX/.github/workflows/gates.yml" <<'YML'
name: gates
on: [pull_request]
jobs:
  gates:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Install npm dependencies
        run: pnpm install --frozen-lockfile
      - name: Install Playwright Chromium
        run: pnpm exec playwright install --with-deps chromium
      - name: Run gates
        run: bash scripts/gates.sh
YML
cat > "$PFIX/.github/workflows/boundaries.yml" <<'YML'
name: boundaries
on: [pull_request]
jobs:
  boundaries:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Check agent boundaries
        run: bash scripts/check-boundaries.sh origin/${{ github.base_ref }}
YML
pdry="$( cd "$PFIX" && bash scripts/ci-local.sh --dry-run 2>&1 )"
assert_contains "a project's install step is run"    "pnpm install --frozen-lockfile" "$pdry"
assert_contains "and its browser install"            "pnpm exec playwright install --with-deps chromium" "$pdry"
assert_contains "alongside the harness's own"        "bash scripts/gates.sh" "$pdry"
# The base_ref expression resolves rather than being passed through literally.
#
# STDOUT ONLY, and the whole resolved command. When the substitution fails the
# step is skipped with a note - on stderr - that quotes the command verbatim:
#   note: skipping a boundaries step this cannot resolve locally:
#     bash scripts/check-boundaries.sh origin/${{ github.base_ref }}
# so a haystack that folds stderr into stdout contains
# `bash scripts/check-boundaries.sh origin/` precisely BECAUSE resolution
# failed. Deleting the substitution outright left this assertion green and was
# caught only by the guard below - which means the thing this one names was not
# the thing it tested.
pout="$( cd "$PFIX" && bash scripts/ci-local.sh --dry-run 2>/dev/null )"
assert_contains "the base ref expression is resolved" \
  "bash scripts/check-boundaries.sh origin/main" "$pout"
case "$pdry" in
  *'${{'*) _bad "no unresolved workflow expression survives" "found one: $pdry" ;;
  *) _ok "no unresolved workflow expression survives" ;;
esac
# And nothing this repository happens to run is invented for a project that
# does not: the fixture's gates.yml has no selftest step.
case "$pdry" in
  *selftest*) _bad "it does not invent steps the workflow lacks" "selftest appeared: $pdry" ;;
  *) _ok "it does not invent steps the workflow lacks" ;;
esac

# A `run: |` block is one step spanning lines, and dropping its body would run a
# truncated command - worse than skipping it.
cat > "$PFIX/.github/workflows/gates.yml" <<'YML'
name: gates
on: [pull_request]
jobs:
  gates:
    runs-on: ubuntu-latest
    steps:
      - name: Two things
        run: |
          bash scripts/selftest.sh
          bash scripts/gates.sh --list
YML
pdry="$( cd "$PFIX" && bash scripts/ci-local.sh --dry-run 2>&1 )"
assert_contains "a block scalar's first line"  "bash scripts/selftest.sh"     "$pdry"
assert_contains "and its second"               "bash scripts/gates.sh --list" "$pdry"
rm -rf "$PFIX"

# PR_HEAD_SHA is not decoration. Without it check-boundaries.sh hashes the
# WORKING TREE, and with it the commit - so a local run that omits it answers a
# different question from the PR check it is standing in for.
assert_contains "it sets PR_HEAD_SHA the way the workflow does" "PR_HEAD_SHA" "$(cat "$SCRIPT")"

# ---------------------------------------------------------------------------
describe "it stops at the first failing step, like a runner"

FIX="$(make_project_fixture)"
mkdir -p "$FIX/.github/workflows"
# Steps are read from the workflows now, so a fixture needs them to have any.
# selftest first, so that stubbing it red exercises the fail-fast path.
cat > "$FIX/.github/workflows/gates.yml" <<'YML'
name: gates
on: [pull_request]
jobs:
  gates:
    runs-on: ubuntu-latest
    steps:
      - name: Harness self-test
        run: bash scripts/selftest.sh
      - name: Run gates
        run: bash scripts/gates.sh
YML
trap 'rm -rf "$FIX"' EXIT
write_conf "$FIX" <<'CONF'
gate     | unit | required | . | printf 'Tests  3 passed (3)\n'
evidence | unit | Tests +[1-9][0-9]* passed
CONF

# The first step, stubbed red. Everything after it must not run: `gates.sh` in
# particular WRITES - it stamps .claude/state/last-gate-run - so "carried on
# after a failure" is observable rather than a matter of reading the output.
printf '#!/usr/bin/env bash\necho "stub selftest: red"\nexit 1\n' > "$FIX/scripts/selftest.sh"
rm -f "$FIX/.claude/state/last-gate-run"
out="$( cd "$FIX" && bash scripts/ci-local.sh 2>&1 )"; rc=$?
assert_eq "a failing first step fails the run" 1 "$rc"
assert_contains "and says which step failed" "selftest" "$out"
if [ -f "$FIX/.claude/state/last-gate-run" ]; then
  _bad "and does not run the steps after it" "gates.sh ran anyway: a stamp was written"
else
  _ok "and does not run the steps after it"
fi

# The failing step's own output has to survive. A wrapper that swallows it and
# prints its own verdict makes every failure a second command to reproduce.
assert_contains "the failing step's output is shown" "stub selftest: red" "$out"

summary "ci-local"
