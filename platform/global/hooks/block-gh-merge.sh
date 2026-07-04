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

# --admin bypasses branch protection entirely — never allowed under any policy.
if echo "$COMMAND" | grep -qE '(^|[[:space:]])--admin\b'; then
  echo "BLOCKED: 'gh pr merge --admin' bypasses branch protection. Never allowed." >&2
  exit 2
fi

# allow-staging: only a bare `gh pr merge` (the CURRENT feature branch's PR into its
# staging base) is allowed. An explicit PR arg (number/URL/branch) merges into THAT PR's
# base — which the `gh pr merge` manual documents, and which may be a protected branch we
# can't cheaply verify here — so block it. Also block when standing on a protected branch.
if [ "$MERGE_POLICY" = "allow-staging" ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  PRODUCTION=$(_get_json_string "production" 2>/dev/null || echo "main")
  if echo "$COMMAND" | grep -qE '\bgh[[:space:]]+pr[[:space:]]+merge[[:space:]]+[^-]'; then
    echo "BLOCKED: In allow-staging mode, only a bare 'gh pr merge' (current branch's PR) is allowed —" >&2
    echo "  an explicit PR target can point at a protected base. Let the user merge that PR." >&2
    exit 2
  fi
  if [ "$BRANCH" = "$PRODUCTION" ] || [ "$BRANCH" = "master" ] || [ "$BRANCH" = "main" ]; then
    echo "BLOCKED: Cannot merge while on production branch '$BRANCH'. Only the user merges production PRs." >&2
    exit 2
  fi
fi

exit 0
