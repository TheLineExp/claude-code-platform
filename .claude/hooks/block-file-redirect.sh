#!/bin/bash
# Block Bash commands that write to files in the main repo via redirects.
# Catches: echo > file, cat > file, tee file, etc.
# This closes the bypass gap where enforce-worktree only catches Edit/Write tools.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no file redirect operators detected
$NEEDS_FILE_CHECK || exit 0

# Only enforce in the main repo (not in worktrees)
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
if echo "$GIT_DIR" | grep -q "/worktrees/"; then
  exit 0  # In a worktree, allow
fi

# Also allow if git-dir is just a file (worktree pointer)
if [ -f "$GIT_DIR" ] 2>/dev/null; then
  exit 0  # Worktree detected via .git file
fi

# Allow writes to .claude/ directory
if echo "$COMMAND" | grep -qE '(>|>>|tee)\s+[^|]*\.claude/'; then
  exit 0
fi

# Allow writes to /dev/null and other non-file targets
if echo "$COMMAND" | grep -qE '(>|>>)\s+/dev/'; then
  exit 0
fi

# Block redirect writes to files in the main repo
if echo "$COMMAND" | grep -qE '\s+(>|>>)\s+[a-zA-Z./]'; then
  echo "BLOCKED: File write via redirect detected in main repo." >&2
  echo "Code modifications must happen in a worktree. Run /letsbuild first." >&2
  exit 2
fi

if echo "$COMMAND" | grep -qE '\btee\s+[a-zA-Z./]'; then
  echo "BLOCKED: File write via 'tee' detected in main repo." >&2
  echo "Code modifications must happen in a worktree. Run /letsbuild first." >&2
  exit 2
fi

exit 0
