#!/bin/bash
# Block gh pr merge commands based on merge policy (configurable).
# Policies: "block-all" (agents never merge), "allow-staging" (allow staging merges only)
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: not a gh command
$NEEDS_GIT_CHECK || exit 0
echo "$COMMAND" | grep -qE '\bgh\s+pr\s+merge\b' || exit 0

source "$SCRIPT_DIR/_config.sh"

if [ "$MERGE_POLICY" = "block-all" ]; then
  echo "BLOCKED: Agents cannot merge PRs. Only the user merges PRs." >&2
  echo "Create the PR and report the URL to the user instead." >&2
  exit 2
fi

# allow-staging policy: block merges to production branches only
if [ "$MERGE_POLICY" = "allow-staging" ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  PRODUCTION=$(_get_json_string "production" 2>/dev/null || echo "main")
  if [ "$BRANCH" = "$PRODUCTION" ]; then
    echo "BLOCKED: Cannot merge to production branch '$PRODUCTION'. Only the user merges production PRs." >&2
    exit 2
  fi
fi

exit 0
