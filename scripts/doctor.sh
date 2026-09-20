#!/usr/bin/env bash
# Check that this machine can actually run the harness and this project.
#
#   bash scripts/doctor.sh
#
# Two layers:
#   1. The harness itself - needs only git and bash.
#   2. The project - every executable named by a gate or task in
#      .claude/harness/project.conf must be on PATH.
#
# Run it after cloning, after picking a stack, and any time a gate fails with
# "command not found".
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/.claude/harness/project.conf"
missing=0
trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

check() { # <executable> <what it is for>
  if command -v "$1" >/dev/null 2>&1; then
    printf '  ok       %-12s %s\n' "$1" "$(command -v "$1")"
  else
    printf '  MISSING  %-12s needed for: %s\n' "$1" "$2"
    missing=$((missing+1))
  fi
}

printf 'Harness prerequisites\n'
check git  "everything"
check bash "the hooks and these scripts"
printf '  ok       %-12s %s\n' "bash ver" "${BASH_VERSION%%(*}"

# Which harness this is. Printed here rather than anywhere else because this is
# the output a project quotes into environment.md and a field report quotes back
# upstream - and the question "which harness did you measure" has now gone
# unanswered twice, at the cost of re-verifying findings that were already fixed.
# An absent stamp is not a blank field: it is a copy from before stamping, which
# is older than every stamped version.
hv="$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$ROOT/.claude/harness/VERSION" 2>/dev/null | head -1)"
hv="$(trim "${hv:-}")"
printf '  ok       %-12s %s\n' "harness ver" "${hv:-unstamped (predates versioning; older than any release)}"

printf '\nHarness integrity\n'
for f in phase-guard.sh inject-state.sh gate-reminder.sh statusline.sh lib.sh; do
  if [ -f "$ROOT/.claude/hooks/$f" ]; then
    if bash -n "$ROOT/.claude/hooks/$f" 2>/dev/null; then
      printf '  ok       %s\n' ".claude/hooks/$f"
    else
      printf '  BROKEN   %s (syntax error)\n' ".claude/hooks/$f"; missing=$((missing+1))
    fi
  else
    printf '  MISSING  %s\n' ".claude/hooks/$f"; missing=$((missing+1))
  fi
done
for f in paths.conf phases.conf models.conf project.conf; do
  [ -f "$ROOT/.claude/harness/$f" ] \
    && printf '  ok       %s\n' ".claude/harness/$f" \
    || { printf '  MISSING  %s\n' ".claude/harness/$f"; missing=$((missing+1)); }
done

printf '\nProject toolchain (from project.conf)\n'
BOOTSTRAPPED="$(grep -E '^BOOTSTRAPPED=' "$CONF" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]')"
seen=""
found_any=0
while IFS= read -r line; do
  case "$(trim "$line")" in ''|'#'*) continue ;; esac
  case "$line" in *'|'*) ;; *) continue ;; esac
  kind=$(trim "$(printf '%s' "$line" | cut -d'|' -f1)")
  case "$kind" in gate|task) ;; *) continue ;; esac
  id=$(trim  "$(printf '%s' "$line" | cut -d'|' -f2)")
  cmd=$(trim "$(printf '%s' "$line" | cut -d'|' -f5-)")
  [ -z "$cmd" ] && continue
  found_any=1
  exe=$(printf '%s' "$cmd" | awk '{print $1}')
  case " $seen " in *" $exe "*) continue ;; esac
  seen="$seen $exe"
  check "$exe" "$kind '$id'"
done < "$CONF"

# --- does CI run the harness's own checks? ----------------------------------
#
# .github/workflows/** is PROJECT-owned: a refresh never touches it, correctly,
# because a project adds its toolchain setup there. The consequence is that the
# template's workflow and the project's diverge from bootstrap onward with
# nothing comparing them - and one real project's CI ran gates.sh but never
# selftest.sh, so the harness's own tests had not executed there once. That is
# how a re-vendor went green with two suites failing.
#
# This lives in doctor rather than in the selftest on purpose: a check that only
# runs inside the suite CI is not running cannot report that CI is not running
# it. doctor is run by hand, at setup, and after a refresh.
#
# It asks only for what the harness cannot do without, and is satisfied by any
# workflow file, because splitting jobs across files is a legitimate layout.
WFDIR="$ROOT/.github/workflows"
if [ -d "$WFDIR" ] && ls "$WFDIR"/*.yml >/dev/null 2>&1; then
  printf 'Continuous integration\n'
  wf_all="$(cat "$WFDIR"/*.yml 2>/dev/null)"
  ci_missing=0
  for want in selftest.sh gates.sh check-boundaries.sh; do
    case "$wf_all" in
      *"scripts/$want"*) ;;
      *)
        printf '  MISSING  %-12s no workflow runs scripts/%s\n' "ci" "$want"
        ci_missing=$((ci_missing+1)) ;;
    esac
  done
  if [ "$ci_missing" -gt 0 ]; then
    printf '  %-10s   those checks are never run on a machine that is not yours\n' ""
    printf '  %-10s   .github/workflows/** is project-owned, so a harness refresh\n' ""
    printf '  %-10s   cannot add them for you - add the steps from the template\n' ""
    missing=$((missing+ci_missing))
  else
    printf '  ok       %-12s runs the self-test, the gates and the boundaries check\n' "ci"
  fi
  printf '\n'
fi

if [ "$found_any" = 0 ] && ! grep -qE '^[[:space:]]*(discovery|artifact)[[:space:]]*\|' "$CONF"; then
  printf '  (nothing configured yet)\n'
  printf '\nproject.conf has no commands, so there is no toolchain to check.\n'
  printf 'This is expected before /plan-product has chosen a stack.\n'
  printf 'Next: /create-product, then /plan-product, then /setup-environment.\n'
  exit 0
fi

printf '\n'
printf '\nProject dependencies\n'
# A global toolchain on PATH is not the same as this project's libraries being
# installed. Checked by manifest: if the manifest exists, its install directory
# must too. Only Node and Python are checked - cargo fetches on build, and Godot
# addons are committed with the project.
#
# Limitation: a monorepo with per-workspace node_modules is not detected here.
dep_found=0
dep_check() { # <manifest> <install dir> <label>
  [ -e "$ROOT/$1" ] || return 0
  dep_found=1
  if [ -e "$ROOT/$2" ]; then
    printf '  ok       %-10s %s present\n' "$3" "$2"
  else
    printf '  MISSING  %-10s %s exists but %s/ is not installed\n' "$3" "$1" "$2"
    printf '  %-10s install them: bash scripts/task.sh install, if project.conf defines that task\n' ""
    missing=$((missing+1))
  fi
}
dep_check package.json      node_modules node
dep_check pyproject.toml    .venv        python
dep_check requirements.txt  .venv        python
[ "$dep_found" = 0 ] && printf '  (no dependency manifests found yet)\n'

printf '\nRequired artifacts\n'
# A gate can be unrunnable on a tree where every tool it names is installed.
#
# The case that produced this section: the `typecheck` gate begins
# `... && test -s globalTypes.d.luau && ...`, that file is generated rather
# than authored, `.gitignore` covers it, and `bash scripts/task.sh install`
# downloads it. So a fresh clone - or a fresh git worktree, which is how it was
# found - never has it, the gate cannot run at all, and doctor printed
# "Everything this project needs is installed" and exited 0. The harness's own
# suite failed 2 of 18 there while CI passed 18 of 18, because CI installs
# first. "Is the toolchain installed?" was answered yes about a tree where a
# REQUIRED gate could not execute.
#
# Two sources, because either alone leaves the hole open:
#
#   DERIVED   every `gate` command is read for `test -s|-d|-e <path>`
#             preconditions. A path git does not carry is checked here. This
#             needs no declaration, so the gap cannot reopen by someone
#             forgetting to write one - which is how `discovery` can still go
#             quiet.
#   DECLARED  an `artifact | <id> | <path> | <remedy>` line in project.conf,
#             for an artifact no `test` guards and to supply the exact remedy.
#
# A PRECONDITION IS NOT A POSTCONDITION, and the difference is the whole
# difficulty. `gate | build` ends `mkdir -p build && rojo build --output
# build/place.rbxl && test -s build/place.rbxl`: it tests a file the same
# command wrote one step earlier, and reporting that as missing would make
# doctor fail on a healthy tree - a false alarm being the one thing that gets a
# check deleted. (`task | install` has the identical shape around
# globalTypes.d.luau. Only `gate` lines are scanned, so that one is not read
# here, but the rule has to hold for a gate written that way and `build` is
# one.) The rule that separates them: a test is a PRECONDITION only when the
# path appears nowhere earlier in the command. Nothing in the command could
# have produced it, so it had to arrive from outside.
art_missing_hint='bash scripts/task.sh install, if project.conf defines that task'
art_found=0
art_seen=""

art_tracked() { # <path> -> 0 when git carries it, so a fresh clone has it
  [ -n "$(git -C "$ROOT" ls-files -- "$1" 2>/dev/null | head -1)" ]
}

art_check() { # <id> <path> <remedy>
  local id="$1" p="$2" remedy="$3" why sz
  case " $art_seen " in *" $p "*) return 0 ;; esac
  art_seen="$art_seen $p"
  art_found=1
  if [ -d "$ROOT/$p" ]; then
    if [ -n "$(ls -A "$ROOT/$p" 2>/dev/null)" ]; then
      printf '  ok       %-12s %s present\n' "$id" "$p"; return 0
    fi
    why="the directory is empty"
  elif [ -e "$ROOT/$p" ]; then
    # Non-emptiness, not existence. A truncated download - an interrupted curl,
    # a proxy that answered 0 bytes - leaves a file that `test -e` accepts and
    # every tool reading it rejects.
    if [ -s "$ROOT/$p" ]; then
      sz="$(wc -c < "$ROOT/$p" 2>/dev/null | tr -d '[:space:]')"
      printf '  ok       %-12s %s present (%s bytes)\n' "$id" "$p" "${sz:-?}"; return 0
    fi
    why="the file is empty"
  else
    why="not present"
  fi
  printf '  MISSING  %-12s %s - %s\n' "$id" "$p" "$why"
  printf '  %-10s   git does not carry it, so a fresh clone or worktree never has it\n' ""
  printf '  %-10s   get it: %s\n' "" "$remedy"
  missing=$((missing+1))
}

# art_preconditions   Command on stdin; the paths it tests for BEFORE anything
# in it could have written them, one per line. Paths holding a `$`, a `*` or a
# `?` are skipped: doctor cannot resolve them, and guessing is worse than the
# gap - `test -d ${GATE_TYPE_TARGET:=src}` is one of these.
art_preconditions() {
  awk '{
    q = sprintf("%c", 39)
    prefix = ""
    for (i = 1; i <= NF; i++) {
      if (($i == "test" || $i == "[") && (i + 2) <= NF) {
        op = $(i + 1); p = $(i + 2)
        gsub(/"/, "", p); gsub(q, "", p); sub(/\]$/, "", p)
        if ((op == "-s" || op == "-d" || op == "-e") \
            && p != "" && p !~ /[$*?]/ && index(prefix, p) == 0)
          print p
      }
      prefix = prefix " " $i
    }
  }'
}

while IFS= read -r line; do
  case "$(trim "$line")" in ''|'#'*) continue ;; esac
  case "$line" in *'|'*) ;; *) continue ;; esac
  kind=$(trim "$(printf '%s' "$line" | cut -d'|' -f1)")
  [ "$kind" = "artifact" ] || continue
  id=$(trim "$(printf '%s' "$line" | cut -d'|' -f2)")
  apath=$(trim "$(printf '%s' "$line" | cut -d'|' -f3)")
  remedy=$(trim "$(printf '%s' "$line" | cut -d'|' -f4-)")
  [ -n "$apath" ] || continue
  art_check "${id:-artifact}" "$apath" "${remedy:-$art_missing_hint}"
done < "$CONF"

while IFS= read -r line; do
  case "$(trim "$line")" in ''|'#'*) continue ;; esac
  case "$line" in *'|'*) ;; *) continue ;; esac
  kind=$(trim "$(printf '%s' "$line" | cut -d'|' -f1)")
  [ "$kind" = "gate" ] || continue
  id=$(trim  "$(printf '%s' "$line" | cut -d'|' -f2)")
  cmd=$(trim "$(printf '%s' "$line" | cut -d'|' -f5-)")
  [ -n "$cmd" ] || continue
  while IFS= read -r apath; do
    [ -n "$apath" ] || continue
    art_tracked "$apath" && continue
    art_check "$id" "$apath" "$art_missing_hint"
  done <<EOF_ART
$(printf '%s\n' "$cmd" | art_preconditions)
EOF_ART
done < "$CONF"

[ "$art_found" = 0 ] && printf '  (none declared, and no gate command tests for one)\n'

printf '\nTest discovery\n'
# A test runner discovers files by glob, and a glob that stops matching says
# nothing: a coverage threshold on a directory no project includes is satisfied
# vacuously, a workspace member dropped from the include list takes its whole
# suite with it, and both look exactly like a clean run. A real instance cost a
# project a directory whose every test was silently never executed.
#
# The rule that catches it: a claim about what a runner DISCOVERS is verified by
# running the runner, never by reading its configuration - reading the config is
# how it stayed invisible. Each `discovery` line in project.conf is such a
# command, and it must exit 0.
disc_found=0
while IFS= read -r line; do
  case "$(trim "$line")" in ''|'#'*) continue ;; esac
  case "$line" in *'|'*) ;; *) continue ;; esac
  kind=$(trim "$(printf '%s' "$line" | cut -d'|' -f1)")
  [ "$kind" = "discovery" ] || continue
  id=$(trim  "$(printf '%s' "$line" | cut -d'|' -f2)")
  cwd=$(trim "$(printf '%s' "$line" | cut -d'|' -f3)"); [ -z "$cwd" ] && cwd="."
  cmd=$(trim "$(printf '%s' "$line" | cut -d'|' -f4-)")
  [ -n "$cmd" ] || continue
  disc_found=1
  # `pipefail` is OFF for a discovery command, and only for a discovery command.
  #
  # These lines end in a matcher by nature - `... | grep -q "src/ui/"` - and
  # `grep -q` exits on its first match. The producer is still writing, takes
  # SIGPIPE, and dies 141; under pipefail that corpse becomes the pipeline's
  # status, and doctor reports "nothing discovered" about a tree where
  # everything is discovered. It is size-dependent, so it passes on a small
  # project and on every fixture in the suite, and starts failing later.
  #
  # A discovery line asks one question - does this find anything - and the
  # matcher's own status is the answer. That is not true of a GATE command,
  # whose status means "did the tool succeed", so gates.sh keeps pipefail: there,
  # a failing test runner whose output still matched would be a vacuous pass.
  if ( set +o pipefail; cd "$ROOT/$cwd" 2>/dev/null && eval "$cmd" ) >/dev/null 2>&1; then
    printf '  ok       %-12s discovered\n' "$id"
  else
    printf '  MISSING  %-12s nothing discovered by: %s\n' "$id" "$cmd"
    printf '  %-10s   tests under it would be committed and never run\n' ""
    missing=$((missing+1))
  fi
done < "$CONF"
[ "$disc_found" = 0 ] && printf '  (none declared; see the discovery format in project.conf)\n'
printf '
'


if [ "$missing" -gt 0 ]; then
  printf '%d thing(s) missing.\n' "$missing"
  [ -f "$ROOT/docs/wiki/environment.md" ] \
    && printf 'Install instructions for this project: docs/wiki/environment.md\n' \
    || printf 'No docs/wiki/environment.md yet. Run /setup-environment to write one.\n'
  exit 1
fi

printf 'Everything this project needs is installed.'
[ "$BOOTSTRAPPED" = "yes" ] || printf ' (project.conf is not bootstrapped yet.)'
printf '\n'
