#!/bin/bash
# Block --no-verify on git commands. Hooks must always run.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# --no-verify only means something on a git command, and matching is per git
# SEGMENT with quoted-string contents blanked — so a commit message that merely
# MENTIONS --no-verify (audit A9, bit twice) or a grep/echo containing the
# literal can never trip this guard.
$NEEDS_GIT_CHECK || exit 0

# Does a git-commit segment carry a REAL no-verify flag? Walks tokens the way
# git's parser does (PR #11 R2 — `git commit -m "-n"` is a MESSAGE, not a flag):
#   - operands of value-taking options (-m/-F/-C/-c/-t and long forms) are skipped
#   - `--` ends option parsing
#   - long form incl. the unambiguous prefixes git accepts (--no-veri, --no-verif)
#   - in a short cluster, a char after a value-taking letter is that option's
#     VALUE (`-mn` = message "n"), while n BEFORE one is --no-verify (`-nm x`)
# Subshell body: set -f stays local (tokens may contain preserved globs).
_commit_no_verify() (
  set -f
  local skip=false tok cluster i ch
  for tok in $1; do
    if [ "$skip" = true ]; then skip=false; continue; fi
    case "$tok" in
      git|commit) continue ;;
      --) break ;;
      --no-veri|--no-verif|--no-verify) return 0 ;;
      -m|-F|-C|-c|-t|--message|--file|--author|--date|--template|--fixup|--squash|--reuse-message|--reedit-message|--trailer|--cleanup|--pathspec-from-file)
        skip=true ;;
      # NOT value-taking as a separate operand: --gpg-sign/-S take an OPTIONAL
      # arg that must be ATTACHED (--gpg-sign=<key>, -S<key>), so a bare
      # --gpg-sign never consumes the next token (PR #11 R3 —
      # `--gpg-sign --no-verify` must still block).
      --*) continue ;;
      -?*)
        cluster="${tok#-}"; i=0
        while [ "$i" -lt "${#cluster}" ]; do
          ch="${cluster:$i:1}"
          case "$ch" in
            n) return 0 ;;
            S) break ;;   # optional ATTACHED value: rest of cluster is the keyid
            m|F|C|c|t)
              [ "$((i+1))" -ge "${#cluster}" ] && skip=true
              break ;;
          esac
          i=$((i+1))
        done ;;
    esac
  done
  return 1
)

while IFS= read -r seg; do
  [ -n "$seg" ] || continue

  if echo "$seg" | grep -qE '^git[[:space:]]+commit([[:space:]]|$)'; then
    if _commit_no_verify "$seg"; then
      echo "BLOCKED: --no-verify (or 'git commit -n') is not allowed. All hooks must run." >&2
      echo "If a hook is failing, fix the underlying issue instead of bypassing it." >&2
      exit 2
    fi
  # Other git subcommands with hook-skipping --no-verify (push, merge), long
  # form incl. unambiguous prefixes. No -n scan here — `git push -n` is
  # --dry-run and `git merge -n` is --no-stat.
  elif echo "$seg" | grep -qE '(^|[[:space:]])--no-veri(f(y)?)?([[:space:]]|$)'; then
    echo "BLOCKED: --no-verify is not allowed. All hooks must run." >&2
    echo "If a hook is failing, fix the underlying issue instead of bypassing it." >&2
    exit 2
  fi
done <<< "$GIT_SEGMENTS"

exit 0
