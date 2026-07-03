#!/bin/bash
# Block git commits on protected branches (configurable via platform.config.json).
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: not a git commit or push command
$NEEDS_GIT_CHECK || exit 0
echo "$COMMAND" | grep -qE '^git (commit|push)\b' || exit 0

source "$SCRIPT_DIR/_config.sh"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Block commits AND pushes while standing on a protected branch. The command
# text alone is not enough — a bare `git push` (or `git commit`) on a checked-out
# protected branch names nothing, so we gate on the CURRENT branch. Protected
# branches deploy via PR, never a direct local push/commit.
for protected in $PROTECTED_BRANCHES; do
  if [ "$BRANCH" = "$protected" ]; then
    if echo "$COMMAND" | grep -qE '^git commit\b'; then
      echo "BLOCKED: Cannot commit on '$BRANCH'. Create a feature branch first." >&2
      echo "  git checkout -b ${FEATURE_PREFIX}your-description" >&2
    else
      echo "BLOCKED: Cannot 'git push' while on protected branch '$BRANCH'." >&2
      echo "  Protected branches deploy via PR, not a direct push." >&2
      echo "  Switch to your feature branch, or open a PR with 'gh pr create'." >&2
    fi
    exit 2
  fi
done

exit 0
