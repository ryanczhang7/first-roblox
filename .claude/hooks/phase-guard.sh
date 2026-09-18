#!/usr/bin/env bash
# PreToolUse hook: enforce the RED -> GREEN phase lock.
#
# While a story is active, this refuses writes that would violate the current
# phase — production code during RED, test edits during GREEN. When no story is
# active it does nothing at all.
#
# It inspects Write/Edit/MultiEdit/NotebookEdit targets directly, and Bash
# commands heuristically (redirects, tee, sed -i, cp/mv, rm, touch), because an
# agent that cannot use Edit will happily reach for `cat > file`.

set -uo pipefail
HOOK_INPUT="$(cat)"
# shellcheck source=lib.sh
# No ERR trap: without set -e bash already continues past failures, so the
# hook degrades to "allow" on any internal problem, which is what we want.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || exit 0


load_state
[ "$PHASE" = "IDLE" ] && exit 0
[ -f "$HARNESS_DIR/paths.conf" ] || exit 0

TOOL="$(json_get_string tool_name || true)"

check_path() {
  local raw="$1" rel cat
  [ -z "$raw" ] && return 0
  rel="$(to_rel "$raw")"
  [ -z "$rel" ] && return 0
  cat="$(classify "$rel")"
  if ! phase_allows "$cat"; then
    deny "BLOCKED by the harness phase lock.

  story:    ${STORY_ID:-unknown}
  phase:    $PHASE
  path:     $rel
  category: $cat

$(phase_message)

If this write is genuinely correct, change the phase deliberately rather than
working around the lock:  bash scripts/phase.sh set ${STORY_ID:-<id>} <PHASE>"
  fi
  return 0
}

# decline <token>   A parse the guard does not believe. It notes the token in
# .claude/state/phase-guard-declined.log and allows the command: a denial
# nobody can act on costs more than the write it might have caught, and the
# note is what turns "the guard is noisy" into a bug report with a token in it.
# Machine-local, like the rest of .claude/state, and never fatal - a hook that
# cannot write its own note still has to let the session continue.
decline() {
  printf 'declined %s in %s: implausible target %s\n' "${STORY_ID:-none}" "$PHASE" "$1" \
    >> "$HARNESS_ROOT/.claude/state/phase-guard-declined.log" 2>/dev/null || true
  return 0
}

case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    check_path "$(json_get_string file_path || true)"
    check_path "$(json_get_string notebook_path || true)"
    ;;
  Bash)
    CMD="$(json_get_string command || true)"
    [ -z "$CMD" ] && exit 0
    # Quoted spans, heredoc bodies and backslash escapes are DATA, not shell
    # syntax. Masking them first is what stops a sed script's `|` or an arrow
    # inside an awk program from being read as an operator; see lib.sh. The
    # extractors below run against the masked text, and each candidate is
    # unmasked again before it is classified.
    MASKED="$(printf '%s' "$CMD" | mask_shell_quotes)"
    # Candidate write targets. Deliberately conservative: we only look at
    # constructs that unambiguously name a destination file.
    #
    # Not by leading command. Exempting `grep`, `awk` and friends as "read-only"
    # is tempting after a run of false positives on them, and it is wrong:
    # `grep -r export src > src/index.ts` writes, and so does every read-only
    # tool on the left of a redirect. What those false positives had in common
    # was quoting, which masking handles, and unparseable output, which
    # path_is_implausible handles. Neither is a property of the command name.
    #
    # Parentheses terminate a target like `;` does: `(cd src && echo x > a.ts)`
    # used to yield `a.ts)`, which the guard declined as unreadable - a hole
    # in the shape of a subshell. `>|` is a redirect too. And `<` ends the
    # rm/touch operand list, because `xargs touch < list` reads `list`.
    # A redirect is the FIRST rule's business and no other rule's. Every rule
    # below it takes a word off the end of its match, and none of them knew a
    # redirect could be attached to the command: `cp a b 2>/dev/null` was refused
    # on a path of `2>/dev/null`, and `rm a 2>/dev/null` on a path of `2`, since
    # that rule's character class excludes `>` and so truncates at it, leaving
    # the file descriptor behind as the candidate. Both were denials of ordinary
    # commands, and the second is the reason this is done here rather than by
    # declining candidates that contain a `>`: such a rule cures `cp` and `mv`
    # and leaves `rm` and `touch` refusing on `2`. Enumerating shapes is how this
    # defect has survived nine of them.
    #
    # So strip redirect clauses once, and let every rule after the first read the
    # stripped text. A quoted `>` is already a control character by now, so only
    # real operators match.
    NOREDIR="$(printf '%s' "$MASKED" | sed -E 's/[0-9]*>>?[[:space:]]*[^|&;()[:space:]]*//g')"
    CANDIDATES="$(
      {
        printf '%s\n' "$MASKED"  | grep -oE '>(>|\|)?[[:space:]]*[^|&;><()[:space:]]+'  | sed -E 's/^>(>|\|)?[[:space:]]*//'
        printf '%s\n' "$NOREDIR" | grep -oE '\btee\b([[:space:]]+-a)?[[:space:]]+[^|&;><()[:space:]]+' | awk '{print $NF}'
        # `sed -i`, decided PER WORD. A word is an option only if it starts with
        # `-`, and that one predicate is the whole of the eleventh shape of this
        # false-positive family. This line used to read
        # `\bsed\b[^|&;()]*-i[^|&;()]*`, which matched `-i` as a bare SUBSTRING
        # anywhere after the word `sed`: `sed -n '1,5p'
        # tests/guards/layer-imports.test.ts` - a pure read - was refused on the
        # file it was READING, because `layer-imports` contains `-i`, while
        # sibling files in the same directory were allowed. A filename is not an
        # option, and the file's contents were never looked at.
        #
        # The substring test was also a HOLE from the other end: `-ni` and `-Ei`
        # contain no `-i` - there is no `-` immediately before the `i` - so a
        # bundled cluster derived NO target at all and `sed -ni 's/a/b/'
        # src/main.ts` rewrote frozen source unchallenged. The false positive
        # and the open hole are the same bug read from two ends. Hence: a
        # single-dash word is in-place when the run of letters after its `-`
        # includes an `i` (`-i`, `-i.bak`, `-ni`, `-Ei`, `-rin`).
        #
        # And the long option is a PREFIX test, never the literal `--in-place`.
        # GNU getopt_long honours any unambiguous abbreviation and `--in-place`
        # is the only long option of GNU sed 4.9 beginning `--i`, so `sed --i`
        # and `sed --in-pl` genuinely write in place (checked against the sed
        # this harness runs on). Matching the literal string would have cured
        # every false positive above and opened a fresh hole in the same commit.
        # It is a prefix rather than a search for the letter because `--silent`
        # - GNU's long form of `-n` - contains an `i` and writes nothing.
        #
        # And the target is not `$NF`. The last word is the file only when sed
        # was handed a script and exactly one file, which is the shape every
        # example is written in and neither of the shapes that broke:
        #
        #   sed --in-place -e 's/a/b/'         $NF is the EXPRESSION - refused
        #                                      as a write to a path `s/a/b`
        #   sed --in-place 's/a/b/' src/main.ts docs/notes.md
        #                                      $NF is the SECOND file, so the
        #                                      write to frozen source passed
        #
        # (Spelt `--in-place` because the portability guard in lib.test.sh
        # greps every shipped script for the GNU-only short form, comments
        # included, and it is right to: a reader copies what is written here.)
        #
        # The same defect from both ends, again: a nonsense denial and an open
        # hole. So the words are read the way sed reads them - options, the
        # argument of an option that takes one, then operands, of which the
        # first is the SCRIPT unless `-e`/`-f` already supplied it - and every
        # file operand is judged rather than the last word.
        printf '%s\n' "$NOREDIR" | grep -oE '\bsed\b[^|&;()]*' \
          | awk '{ inplace = 0; scripted = 0; nops = 0; skip = 0
                   for (i = 2; i <= NF; i++) {          # $1 is `sed` itself
                     w = $i
                     if (skip) { skip = 0; continue }   # an option argument
                     if (w ~ /^--/) {
                       o = w; att = (index(o, "=") > 0)
                       sub(/=.*$/, "", o); sub(/^--/, "", o)
                       if (o == "") continue
                       if      (index("in-place", o)   == 1) inplace = 1
                       else if (index("expression", o) == 1) { scripted = 1; if (!att) skip = 1 }
                       else if (index("file", o)       == 1) { scripted = 1; if (!att) skip = 1 }
                       continue
                     }
                     if (w ~ /^-./) {
                       c = w; sub(/^-/, "", c)
                       # A short cluster, read left to right until a letter
                       # swallows the rest of the word: `-i` takes the rest as
                       # its backup SUFFIX (`-i.bak`), `-e` and `-f` take it as
                       # their argument (`-e s/a/b/`), or the next word when
                       # they end the cluster.
                       for (k = 1; k <= length(c); k++) {
                         ch = substr(c, k, 1)
                         if (ch == "i") { inplace = 1; break }
                         if (ch == "e" || ch == "f") {
                           scripted = 1
                           if (k == length(c)) skip = 1
                           break
                         }
                       }
                       continue
                     }
                     nops++; op[nops] = w
                   }
                   if (!inplace) next
                   for (k = 1; k <= nops; k++) {
                     if (k == 1 && !scripted) continue  # the script, not a file
                     print op[k]
                   } }'
        printf '%s\n' "$NOREDIR" | grep -oE '\b(cp|mv)\b[[:space:]]+[^|&;()]+'         | awk '{print $NF}'
        # Words, minus the command, minus options - and minus the ARGUMENT of an
        # option that takes one. That last clause is the tenth shape of the
        # false-positive family: `touch -t 202601010000 docs/a.md` was refused on
        # a path of `202601010000`, and `touch -r src/main.ts docs/a.md` on
        # `src/main.ts` - which `-r` only READS, so the denial pointed at a real
        # file the command never writes. A wrong denial naming a real path is the
        # most convincing kind, because the message looks right.
        printf '%s\n' "$NOREDIR" | grep -oE '\b(rm|touch)\b[[:space:]]+[^|&;<>()]+' \
          | awk '{ skip = 0
                   for (i = 1; i <= NF; i++) {
                     w = $i
                     if (skip) { skip = 0; continue }
                     if (w ~ /^(rm|touch)$/) continue
                     if (w ~ /^-/) {
                       if (w ~ /^(-t|-d|-r|--date|--reference|--time)$/) skip = 1
                       continue
                     }
                     print w
                   } }'
      } 2>/dev/null | tr -d '"'"'" | grep -vE '^\s*$|^-|\*|^/dev/' | sort -u
    )"
    # `$` is no longer filtered out here. It was, silently, which made the ONE
    # recipe the harness pushes an agent towards in RED - mutate the production
    # file, watch the corrected test fail, revert - pass unchecked. A candidate
    # whose variable the command text assigns is resolved; one it does not is
    # declined and logged, which is what the guard already does with every other
    # parse it cannot believe. See lib.sh.
    ASSIGNMENTS="$(shell_assignments "$MASKED")"
    # The FILE argument of a scripts/mutate.sh invocation, resolved the same way
    # so that `mutate.sh "$F"` is exempt for the same reason `mutate.sh src/a.ts`
    # is. Only that argument: the payload after `--` is judged normally.
    EXEMPT=""
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      EXEMPT="$EXEMPT
$(resolve_vars "$m" "$ASSIGNMENTS")"
    done <<< "$(mutate_targets "$MASKED")"
    # Where the shell will actually be when those targets are written. A
    # relative path means nothing without it: `cd /tmp/scratch && rm -rf
    # gate-logs` names no repo path at all. An unaccountable cwd skips relative
    # candidates rather than blocking them - fail open.
    CWD_PREFIX=""; CWD_KNOWN=1
    CWD_PREFIX="$(command_cwd "$MASKED")" || CWD_KNOWN=0
    while IFS= read -r target; do
      [ -z "$target" ] && continue
      # Resolved before it is judged, so that `"$F"` is either a real path or an
      # honest decline. Still masked at this point, so a value carrying a quoted
      # space survives as one token.
      target="$(resolve_vars "$target" "$ASSIGNMENTS")"
      case "
$EXEMPT" in *"
$target"*) continue ;; esac
      # Judged while still masked: a metacharacter that survives to here was
      # leaked by the parse rather than quoted by the author. An implausible
      # token means the parse failed, and a failed parse is inconclusive, not
      # a violation - see path_is_implausible in lib.sh.
      if path_is_implausible "$target"; then decline "$target"; continue; fi
      target="$(printf '%s' "$target" | unmask_shell_quotes)"
      # A restored candidate spanning a newline is not a filename; a guard that
      # cannot say what it is looking at does not block. Fail open, as ever.
      case "$target" in *$'\n'*) continue ;; esac
      if path_is_absolute "$target"; then
        check_path "$target"
      elif [ "$CWD_KNOWN" = 1 ]; then
        target="$(normalize_rel "${CWD_PREFIX:+$CWD_PREFIX/}$target")" || continue
        check_path "$target"
      fi
    done <<< "$CANDIDATES"
    ;;
esac

exit 0
