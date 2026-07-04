#!/bin/bash
# Block destructive git operations: force push, hard reset, checkout ., clean.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: not a git command
$NEEDS_GIT_CHECK || exit 0

# Allow --force-with-lease (the safe variant — refuses if the remote has commits
# the local doesn't know about). Unblocks the legitimate "rebase your feature
# branch, then push" workflow. Must come BEFORE the block, since the block regex
# would otherwise match the literal "--force" prefix. Plain --force / -f stay blocked.
if echo "$COMMAND" | grep -qE 'git push.*--force-with-lease(\b|=)'; then
  exit 0
fi

if echo "$COMMAND" | grep -qE 'git push.*--force|git push.*-f\b'; then
  echo "BLOCKED: Force push not allowed. Use --force-with-lease, a regular push, or a new branch." >&2
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

# git clean force — including combined short flags (`-xdf`, `-df`) and `--force`.
if echo "$COMMAND" | grep -qE 'git clean\b.*(-[a-zA-Z]*f|--force)'; then
  echo "BLOCKED: 'git clean' with force permanently deletes untracked files." >&2
  exit 2
fi

exit 0
