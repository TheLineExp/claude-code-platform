#!/bin/bash
# Block interactive rebase and hunk-picker modes (require a TTY, not supported
# in Claude Code).
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no real git command segment. Flags are matched INSIDE the git
# segment only — the old raw-command grep matched `git checkout -b x && mkdir -p y`
# because the `-p` of mkdir sat after `git checkout` in the same string (the
# audit-A9 cross-matching class).
$NEEDS_GIT_CHECK || exit 0

while IFS= read -r seg; do
  [ -n "$seg" ] || continue

  if echo "$seg" | grep -qE '^git[[:space:]]+rebase([[:space:]]|$)' && \
     echo "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*i[a-zA-Z]*|--interactive)([[:space:]]|$)'; then
    echo "BLOCKED: Interactive rebase requires a terminal and is not supported in Claude Code." >&2
    echo "Use 'git rebase <branch>' (non-interactive) instead." >&2
    exit 2
  fi

  # Interactive/patch hunk selection is TTY-only. `-i`/`--interactive` for
  # add/stash; `-p`/`--patch` for add/stash AND checkout/restore/reset.
  if echo "$seg" | grep -qE '^git[[:space:]]+(add|stash)([[:space:]]|$)' && \
     echo "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*i[a-zA-Z]*|--interactive)([[:space:]]|$)'; then
    echo "BLOCKED: Interactive mode requires a terminal and is not supported in Claude Code." >&2
    exit 2
  fi
  if echo "$seg" | grep -qE '^git[[:space:]]+(add|stash|checkout|restore|reset)([[:space:]]|$)' && \
     echo "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*p[a-zA-Z]*|--patch)([[:space:]]|$)'; then
    echo "BLOCKED: Patch mode (-p/--patch) requires a terminal and is not supported in Claude Code." >&2
    exit 2
  fi
done <<< "$GIT_SEGMENTS"

exit 0
