#!/bin/bash
# Block gh pr merge. Policy is HARDCODED block-all (agents never merge PRs —
# doctrine; see _config.sh for the decision record). The old allow-staging
# branch is gone with the deleted platform.config.json.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no real gh command segment. Per-segment matching (POSIX classes
# only — the old `\s` was GNU-specific and failed open on BSD grep, audit A10).
$NEEDS_GIT_CHECK || exit 0
echo "$GIT_SEGMENTS" | grep -qE '^gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' || exit 0

echo "BLOCKED: Agents cannot merge PRs. Only the user merges PRs." >&2
echo "Create the PR and report the URL to the user instead." >&2
exit 2
