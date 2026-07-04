#!/bin/bash
# Block interactive rebase (requires TTY, not supported in Claude Code)
# and force-with-lease (still destructive, just safer).
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: not a git command
$NEEDS_GIT_CHECK || exit 0

if echo "$COMMAND" | grep -qE 'git rebase.*(-i\b|--interactive)'; then
  echo "BLOCKED: Interactive rebase requires a terminal and is not supported in Claude Code." >&2
  echo "Use 'git rebase <branch>' (non-interactive) instead." >&2
  exit 2
fi

# Interactive/patch hunk selection is TTY-only. `-i`/`--interactive` for add/stash;
# `-p`/`--patch` for add/stash AND checkout/restore/reset (all enter the hunk picker).
if echo "$COMMAND" | grep -qE 'git (add|stash)\b.*(-i\b|--interactive\b)'; then
  echo "BLOCKED: Interactive mode requires a terminal and is not supported in Claude Code." >&2
  exit 2
fi
if echo "$COMMAND" | grep -qE 'git (add|stash|checkout|restore|reset)\b.*(-p\b|--patch\b)'; then
  echo "BLOCKED: Patch mode (-p/--patch) requires a terminal and is not supported in Claude Code." >&2
  exit 2
fi

exit 0
