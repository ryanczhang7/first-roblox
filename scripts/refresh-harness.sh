#!/usr/bin/env bash
# Copy a newer harness into a project that is already using one.
#
#   bash scripts/refresh-harness.sh ../agentic-dev-harness
#   bash scripts/refresh-harness.sh --dry-run ../agentic-dev-harness
#
# Run it FROM the project being refreshed, with the path to a checkout of the
# harness. It is the README's procedure, executable, and it exists because that
# procedure was prose and prose was followed wrongly on its first real outing -
# by the agent that had written it, a day earlier. Three separate ways:
#
#   * it recommended `rsync`, which is not present in Git Bash, the shell this
#     harness runs in on Windows;
#   * a wholesale replace of `.claude/skills` deletes a project's OWN stack
#     profile - the one in the way was 17 KB and cited by four documents, and
#     nothing would have said a word;
#   * it omitted `.claude/settings.json` and `.claude/state/README.md`, which are
#     upstream-owned and read as evidence by the settings suite.
#
# Each was a step somebody had to get right by reading carefully, which is a
# requirement this repository does not accept anywhere else.
#
# Three kinds of file, and the middle one is the reason this is not a `cp -r`:
#
#   REPLACED  upstream owns it outright
#   KEPT      inside a replaced directory, but upstream does not ship it, so it
#             is the project's and survives
#   LEFT      project-owned, or needs a human: project.conf, docs, .gitignore,
#             .github/workflows, and the two that must be MERGED rather than
#             copied - paths.conf and CLAUDE.md

set -uo pipefail

# This script replaces scripts/*.sh, and one of those is this file.
#
# Bash reads a script by byte offset as it executes it. Overwrite the file
# underneath and execution resumes at the old offset in the NEW bytes: mid-line,
# mid-block, as whatever that happens to parse as. The first real refresh to hit
# this printed `line 151: ------------: command not found` and ran its
# single-file block a second time; the fixture in refresh.test.sh, with
# different padding, gets a syntax error and dies half way through instead. The
# tree came out correct that once only because the re-entered block was
# idempotent `cp` calls. A few hundred bytes the other way is the `rm -rf` loop
# re-entered with different state, in the one script whose whole purpose is not
# destroying a project's files without saying so.
#
# So run from a private copy. Then the file being READ is never the file being
# WRITTEN, whatever the copy loop does to scripts/. `$0` stays a file with
# identical content, so `--help` still reads its own header out of it.
# The copy goes to a path this script NAMES, under the machine-local state
# directory the harness already owns - not to $TMPDIR and not through mktemp.
# That variable is unset in some of the shells this runs in, and the one place
# it mattered, a mutation backup, lost its backup to exactly that. lib.test.sh
# enforces the rule; .claude/state/README.md carries the row.
if [ -z "${REFRESH_SELF_COPY:-}" ]; then
  _self="$(pwd)/.claude/state/refresh-self.$$.sh"
  if mkdir -p "$(pwd)/.claude/state" 2>/dev/null && cp "$0" "$_self" 2>/dev/null; then
    REFRESH_SELF_COPY="$_self" exec bash "$_self" "$@"
  fi
  # Could not make the copy. Carry on in place rather than refusing: a refresh
  # that runs with this hazard beats one that cannot run at all, and the hazard
  # is only reachable once the copy loop is already underway.
  rm -f "$_self" 2>/dev/null
fi
[ -n "${REFRESH_SELF_COPY:-}" ] && trap 'rm -f "$REFRESH_SELF_COPY"' EXIT

PROJ="$(pwd)"
DRY=0
UP=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) printf 'refresh-harness: unknown option %s\n' "$a" >&2; exit 2 ;;
    *) UP="$a" ;;
  esac
done

die() { printf 'refresh-harness: %s\n' "$1" >&2; exit 2; }

[ -n "$UP" ] || die "give me the path to a harness checkout: refresh-harness.sh ../agentic-dev-harness"
[ -d "$UP/.claude/hooks" ] && [ -d "$UP/scripts" ] \
  || die "'$UP' does not look like a harness checkout (no .claude/hooks, no scripts)"

# THE PROCEDURE BELONGS TO THE RELEASE BEING INSTALLED, not to the one you are
# leaving. A refresh is normally driven by the project's own copy of this
# script, and that copy is one release behind BY CONSTRUCTION: a change to
# *what* gets copied only takes effect on the refresh AFTER the one that
# delivers it.
#
# Not hypothetical. `.claude/harness/models.conf` joined the single-file list in
# release 23, so a project on 22 running its own script received
# `scripts/plan.sh` without the policy file plan.sh reads - a script delivered
# without the thing it depends on, silently. Every future addition to that list
# has the same one-release delay, and "remember to run upstream's copy" is not a
# mechanism; it is a thing to forget.
#
# So hand over. Upstream's copy knows what upstream ships.
#
# IT TERMINATES ON THE COMPARISON ALONE, and there is deliberately no second
# guard. The script handed to reads `$0` as upstream's file - or as a self-copy
# of it - so `cmp` finds them identical and it takes the other branch. An
# environment flag was here first, and removing it left all 49 assertions green:
# a line nothing can fail is a line whose behaviour nobody has checked, and
# belt-and-braces that cannot be falsified is just braces nobody has looked at.
# What holds this up is the control in refresh.test.sh - identical copies hand
# over to nobody - which is the assertion that goes red if this comparison
# breaks.
#
# REFRESH_SELF_COPY is cleared so the new process makes its own, which matters
# only in the degenerate case where UP and PROJ are the same tree.
UP_SELF="$UP/scripts/refresh-harness.sh"
if [ -f "$UP_SELF" ] && ! cmp -s "$UP_SELF" "$0"; then
  printf 'refresh-harness: upstream ships a different refresh-harness.sh; running that one.\n'
  printf '  A change to WHAT this copies would otherwise take effect one release late.\n\n'
  [ -n "${REFRESH_SELF_COPY:-}" ] && rm -f "$REFRESH_SELF_COPY"
  REFRESH_SELF_COPY= exec bash "$UP_SELF" "$@"
fi

# Refusing rather than warning, on both counts below. A warning at the top of a
# wall of output is a warning nobody reads, and both of these end with a tree
# somebody has to reconstruct by hand.
if [ "$DRY" = 0 ] && git -C "$PROJ" rev-parse --git-dir >/dev/null 2>&1; then
  if [ -n "$(git -C "$PROJ" status --porcelain 2>/dev/null | grep -v '^??')" ]; then
    die "this tree has uncommitted changes. Commit or stash them first - this rewrites
  a lot of files at once, and you want a clean diff to read afterwards."
  fi
fi

# The procedure's own rule, enforced instead of requested: never mid-cycle. The
# hooks being replaced are the ones enforcing the phase the story is standing in.
STATE="$PROJ/.claude/state/current-story.env"
if [ "$DRY" = 0 ] && [ -f "$STATE" ]; then
  ph="$(sed -nE 's/^PHASE=//p' "$STATE" | head -1 | tr -d '[:space:]')"
  sid="$(sed -nE 's/^STORY_ID=//p' "$STATE" | head -1 | tr -d '[:space:]')"
  case "$ph" in
    ""|DONE) ;;
    *) die "story ${sid:-?} is in $ph. Refresh between stories, never mid-cycle: the hooks
  this replaces are the ones enforcing the phase that story is standing in.
  Finish it, or clear the lock with: bash scripts/phase.sh clear" ;;
  esac
fi

say() { printf '%s\n' "$1"; }
act() { [ "$DRY" = 1 ] || eval "$1"; }

upstream_version="$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$UP/.claude/harness/VERSION" 2>/dev/null | head -1)"
current_version="$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$PROJ/.claude/harness/VERSION" 2>/dev/null | head -1)"
say "refresh-harness${DRY:+}$([ "$DRY" = 1 ] && printf ' (dry run)')"
say "  from: $UP  (${upstream_version:-unstamped})"
say "  into: $PROJ  (${current_version:-unstamped - predates versioning})"
say ""

kept_any=0

# --- directories upstream owns, except for what it does not ship -------------
for d in agents commands skills hooks tests; do
  src="$UP/.claude/$d"; dst="$PROJ/.claude/$d"
  [ -d "$src" ] || continue
  if [ -d "$dst" ]; then
    # Anything here that upstream does not ship belongs to the project. This is
    # the whole reason the script exists: a directory replace is silent about it.
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      [ -e "$src/$rel" ] && continue
      say "  KEPT      .claude/$d/$rel  (upstream does not ship it - yours)"
      kept_any=1
    done <<< "$(cd "$dst" && find . -type f 2>/dev/null | sed 's|^\./||')"
  fi
done

# Preserve, replace, restore. Done in one pass per directory so that a failure
# leaves the project's own files somewhere findable rather than nowhere.
KEEP="$PROJ/.claude/.refresh-keep.$$"
if [ "$DRY" = 0 ]; then
  rm -rf "$KEEP"; mkdir -p "$KEEP"
  for d in agents commands skills hooks tests; do
    src="$UP/.claude/$d"; dst="$PROJ/.claude/$d"
    [ -d "$src" ] && [ -d "$dst" ] || continue
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      [ -e "$src/$rel" ] && continue
      mkdir -p "$KEEP/$d/$(dirname "$rel")"
      cp "$dst/$rel" "$KEEP/$d/$rel"
    done <<< "$(cd "$dst" && find . -type f 2>/dev/null | sed 's|^\./||')"
  done
fi

# One loop decides and reports. It used to be two - a copy loop inside the
# dry-run guard, and a report loop outside it walking a second copy of the same
# list - with nothing tying them together, so shortening the copy loop left the
# report printing `REPLACED .claude/hooks/` over a hook that had not been
# touched. A refresh that silently skips the phase lock and then says it updated
# it is the worst thing this script can do. The report is now a side effect of
# the work rather than a second opinion about it.
replaced_dirs=""
for d in agents commands skills hooks tests; do
  [ -d "$UP/.claude/$d" ] || continue
  if [ "$DRY" = 0 ]; then
    rm -rf "$PROJ/.claude/$d"
    cp -r "$UP/.claude/$d" "$PROJ/.claude/$d"
  fi
  replaced_dirs="$replaced_dirs $d"
done

if [ "$DRY" = 0 ] && [ -d "$KEEP" ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$PROJ/.claude/$(dirname "$rel")"
    cp "$KEEP/$rel" "$PROJ/.claude/$rel"
  done <<< "$(cd "$KEEP" && find . -type f 2>/dev/null | sed 's|^\./||')"
  rm -rf "$KEEP"
fi

for d in $replaced_dirs; do say "  REPLACED  .claude/$d/"; done

# --- single files upstream owns ---------------------------------------------
for f in .claude/harness/phases.conf .claude/harness/models.conf \
         .claude/harness/rules.md .claude/harness/VERSION \
         .claude/settings.json .claude/state/README.md; do
  [ -f "$UP/$f" ] || continue
  act "mkdir -p \"$PROJ/$(dirname "$f")\" && cp \"$UP/$f\" \"$PROJ/$f\""
  say "  REPLACED  $f"
done

# scripts/*.sh only: a project legitimately adds its own scripts, and its own
# subdirectories, and a directory replace would take them.
for f in "$UP"/scripts/*.sh; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  act "cp \"$f\" \"$PROJ/scripts/$b\""
done
say "  REPLACED  scripts/*.sh  (your own scripts and subdirectories untouched)"
say ""

# --- what a human still has to do -------------------------------------------
say "  LEFT for you to merge by hand - do not just copy these:"
say "    .claude/harness/paths.conf   upstream's rules PLUS your project's globs."
say "                                 Take upstream as the base and append yours,"
say "                                 so upstream wins on any overlap."
say "    CLAUDE.md                    mostly upstream's, but its tables describe"
say "                                 the template's own conventions. Read it"
say "                                 before keeping a row that is about the"
say "                                 harness repository rather than about you."
say ""
say "  LEFT untouched (project-owned): .claude/harness/project.conf, docs/**,"
say "    .gitignore, .github/workflows/**, and everything outside .claude and scripts."
say ""

if [ "$DRY" = 1 ]; then
  say "Dry run: nothing was written."
  exit 0
fi

say "Now, in this order:"
say "  bash scripts/selftest.sh        the machinery everything else depends on,"
say "                                  and the file set you just replaced"
say "  bash scripts/doctor.sh          also tells you whether CI runs these checks"
say "  bash scripts/gates.sh           your project, under the new harness"
[ "$kept_any" = 1 ] && say "" && say "Read the KEPT lines above before you commit: those files are yours, and a
directory replace would have deleted them without a word."
exit 0
