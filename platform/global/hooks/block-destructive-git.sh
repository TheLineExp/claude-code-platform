#!/bin/bash
# Block destructive git operations: force push, forced (+) refspecs, hard reset,
# checkout/restore of the whole tree, clean --force.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no real git command segment. All matching below is per SEGMENT with
# quoted-string contents blanked — a commit message or echo/grep argument that
# merely CONTAINS "--force" or "git reset --hard" never trips this guard
# (audit A9, which blocked the audit itself twice).
$NEEDS_GIT_CHECK || exit 0

while IFS= read -r seg; do
  [ -n "$seg" ] || continue

  if echo "$seg" | grep -qE '^git[[:space:]]+push([[:space:]]|$)'; then
    # Forced refspec (audit A4): `git push origin +HEAD:x` / `+branch`
    # force-updates without any --force flag. Blocked regardless of
    # --force-with-lease, which does NOT make a `+` refspec safe.
    if echo "$seg" | grep -qE '[[:space:]]\+[^[:space:]]+'; then
      echo "BLOCKED: forced refspec ('+...') force-updates the remote ref. Use a regular push or a new branch." >&2
      exit 2
    fi
    # --force-with-lease is the safe variant (refuses if the remote moved) —
    # allow it, including the unambiguous prefixes git accepts (--force-w…).
    if echo "$seg" | grep -qE '(^|[[:space:]])--force-w[a-z-]*(=[^[:space:]]*)?([[:space:]]|$)'; then
      continue
    fi
    # Plain --force (exact: --forc/--fo are ambiguous and git rejects them)
    # or -f, including bundled short-flag clusters.
    if echo "$seg" | grep -qE '(^|[[:space:]])(--force|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)'; then
      echo "BLOCKED: Force push not allowed. Use --force-with-lease, a regular push, or a new branch." >&2
      exit 2
    fi
  fi

  # reset --hard, including the unambiguous long-option prefixes git accepts:
  # --h / --ha / --har (audit A5).
  if echo "$seg" | grep -qE '^git[[:space:]]+reset([[:space:]]|$)' && \
     echo "$seg" | grep -qE '(^|[[:space:]])--h(a(r(d)?)?)?([[:space:]]|$)'; then
    echo "BLOCKED: Hard reset not allowed. Use 'git stash' or 'git checkout <file>' for specific files." >&2
    exit 2
  fi

  # checkout/restore of the WHOLE tree (audit A6): `.`, `./`, `..`, `-- .`,
  # and the repo-root pathspec `:/` — with or without trailing space. A path
  # that merely STARTS with a dot (.github/) does not match.
  if echo "$seg" | grep -qE '^git[[:space:]]+(checkout|restore)([[:space:]]|$)' && \
     echo "$seg" | grep -qE '[[:space:]](--[[:space:]]+)?(\.{1,2}/?|:/)([[:space:]]|$)'; then
    echo "BLOCKED: checkout/restore of the whole tree discards all changes. Use 'git stash' instead." >&2
    exit 2
  fi

  # git clean force — including combined short flags (`-xdf`, `-df`) and --force.
  if echo "$seg" | grep -qE '^git[[:space:]]+clean([[:space:]]|$)' && \
     echo "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*f[a-zA-Z]*|--force)([[:space:]]|$)'; then
    echo "BLOCKED: 'git clean' with force permanently deletes untracked files." >&2
    exit 2
  fi
done <<< "$GIT_SEGMENTS"

exit 0
