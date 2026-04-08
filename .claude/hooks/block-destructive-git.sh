#!/bin/bash
# Block destructive git operations: force push, hard reset, checkout ., clean.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: not a git command
$NEEDS_GIT_CHECK || exit 0

if echo "$COMMAND" | grep -qE 'git push.*--force|git push.*-f\b|git push.*--force-with-lease'; then
  echo "BLOCKED: Force push not allowed. Use a regular push or create a new branch." >&2
  exit 2
fi

if echo "$COMMAND" | grep -qE 'git reset.*--hard'; then
  echo "BLOCKED: Hard reset not allowed. Use 'git stash' or 'git checkout <file>' for specific files." >&2
  exit 2
fi

if echo "$COMMAND" | grep -qE 'git checkout \.$'; then
  echo "BLOCKED: 'git checkout .' discards all changes. Use 'git stash' instead." >&2
  exit 2
fi

if echo "$COMMAND" | grep -qE 'git clean.*-f'; then
  echo "BLOCKED: 'git clean -f' permanently deletes untracked files." >&2
  exit 2
fi

exit 0
