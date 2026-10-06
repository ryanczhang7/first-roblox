#!/usr/bin/env bash
# Report every uncommitted .luau file under src/, tests/ and lune/.
#
#   bash scripts/stray-luau.sh [<repo-root>]     porcelain lines, one per line
#
# <repo-root> defaults to this script's parent directory. Every line of
# `git status --porcelain` whose path ends in `.luau` is printed unchanged
# (`?? src/shared/B.luau`, ` M src/shared/A.luau`, `R  old -> new.luau`).
# Success is status 0 whether or not anything printed - the caller decides what
# "stray" means - and stderr stays silent. If <repo-root> is not a directory or
# git status fails, it prints `stray-luau: cannot read git status in <root>`
# and git's own stderr to stderr, and exits with status 2.
#
# WHY IT EXISTS (HARNESS-023). Two suites that pin counter baselines over the
# real tree open with a precondition that the tree carries no stray .luau
# files. It was an inline pipeline - `git status --porcelain -- ... | grep
# '\.luau$' || true` - with two holes:
#
#   - default untracked mode `normal` collapses a NEW directory to one line,
#     `?? src/shared/channel/`, which does not end in .luau, so a new module in
#     a new directory was never reported. `--untracked-files=all` lists every
#     file, and on the command line it also overrides a repo's
#     `status.showUntrackedFiles` setting.
#   - `|| true` swallowed a failing git as well as an empty grep, so a
#     precondition whose instrument never ran reported a clean tree. Here git's
#     status is taken on its own, before any filtering, and a failure is loud.
#
# git's stderr is discarded on the first run and shown only on failure: the
# call sites merge stderr into what they compare against "", so a warning on a
# successful run (CRLF notices on Windows) would otherwise turn a clean tree
# into a stray one. On failure the same read-only git status is run a second
# time with its stderr passed through and its stdout discarded, so the error
# is shown without a capture file - nothing shipped writes to a temporary
# directory it did not name itself (lib.test.sh).
#
# Ignored files are not reported (git's default). Paths git has to quote
# (spaces, non-ASCII) end in `.luau"` and are not matched; no module here has
# such a name.
set -uo pipefail

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

status_args=(status --porcelain --untracked-files=all -- src tests lune)

failed=0
isdir=1
if [ -d "$root" ]; then
  out="$(git -C "$root" "${status_args[@]}" 2>/dev/null)" || failed=1
else
  isdir=0
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  printf 'stray-luau: cannot read git status in %s\n' "$root" >&2
  if [ "$isdir" -eq 1 ]; then
    git -C "$root" "${status_args[@]}" >/dev/null
  else
    printf 'not a directory: %s\n' "$root" >&2
  fi
  exit 2
fi

[ -n "$out" ] || exit 0
printf '%s\n' "$out" | awk '/\.luau$/'
