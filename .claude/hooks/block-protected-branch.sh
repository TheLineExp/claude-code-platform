#!/bin/bash
# Block git commits on protected branches (configurable via platform.config.json).
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: not a git commit command
$NEEDS_GIT_CHECK || exit 0
echo "$COMMAND" | grep -qE '^git commit\b' || exit 0

source "$SCRIPT_DIR/_config.sh"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

for protected in $PROTECTED_BRANCHES; do
  if [ "$BRANCH" = "$protected" ]; then
    echo "BLOCKED: Cannot commit on '$BRANCH'. Create a feature branch first." >&2
    echo "  git checkout -b ${FEATURE_PREFIX}your-description" >&2
    exit 2
  fi
done

exit 0
