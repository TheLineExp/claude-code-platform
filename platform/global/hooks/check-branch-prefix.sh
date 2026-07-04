#!/bin/bash
# Verify that the feature branch prefix matches the agent's window ID.
# Configurable owner prefixes are always allowed (for human commits).
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: only check on git commit
$NEEDS_GIT_CHECK || exit 0
echo "$COMMAND" | grep -qE '^git commit\b' || exit 0

# Global deployment: only enforce where the letsbuild workflow is active.
_fleet_active || exit 0

source "$SCRIPT_DIR/_config.sh"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Only check feature branches
if ! echo "$BRANCH" | grep -q "^${FEATURE_PREFIX}"; then
  exit 0
fi

# Extract prefix from branch: feature/w1-description → w1
BRANCH_PREFIX=$(echo "$BRANCH" | sed "s|^${FEATURE_PREFIX}||" | sed 's/-.*//')

# Allow configurable owner prefixes (human commits)
for owner in $OWNER_PREFIXES; do
  if [ "$BRANCH_PREFIX" = "$owner" ]; then
    exit 0
  fi
done

# Allow cross-repo prefix (x1, x2...) when window-id is also cross-repo
if [[ "$BRANCH_PREFIX" == x* ]]; then
  WINDOW_ID_FILE=".claude/window-id"
  if [ -f "$WINDOW_ID_FILE" ]; then
    WID=$(cat "$WINDOW_ID_FILE" 2>/dev/null | tr -d '[:space:]')
    if [[ "$WID" == x* ]]; then
      exit 0
    fi
  fi
fi

# Allow solo prefix when window-id is 's'
if [ "$BRANCH_PREFIX" = "s" ]; then
  WINDOW_ID_FILE=".claude/window-id"
  if [ -f "$WINDOW_ID_FILE" ]; then
    WID=$(cat "$WINDOW_ID_FILE" 2>/dev/null | tr -d '[:space:]')
    if [ "$WID" = "s" ]; then
      exit 0
    fi
  fi
fi

# Check window ID file
WINDOW_ID_FILE=".claude/window-id"
if [ ! -f "$WINDOW_ID_FILE" ]; then
  exit 0  # No window-id file, skip check
fi

WINDOW_ID=$(cat "$WINDOW_ID_FILE" 2>/dev/null | tr -d '[:space:]')
if [ -z "$WINDOW_ID" ] || [ "$WINDOW_ID" = "setup" ]; then
  exit 0  # Setup mode or empty, skip check
fi

if [ "$BRANCH_PREFIX" != "$WINDOW_ID" ]; then
  echo "BLOCKED: Branch prefix '$BRANCH_PREFIX' doesn't match window ID '$WINDOW_ID'." >&2
  echo "You are window $WINDOW_ID but trying to commit on a $BRANCH_PREFIX branch." >&2
  echo "Switch to your assigned branch or run /letsbuild to get a new assignment." >&2
  exit 2
fi

exit 0
