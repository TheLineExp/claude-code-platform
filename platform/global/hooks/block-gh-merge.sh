#!/bin/bash
# Block gh pr merge. Policy is HARDCODED block-all (agents never merge PRs —
# doctrine; see _config.sh for the decision record).
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no real gh command. Matching is on ARGV TOKENS, so a `git commit -m
# "gh pr merge later"` message can never trip this guard (audit A9/A10).
$NEEDS_GIT_CHECK || exit 0

_gm_check() {
  [ "${CMD_ARGV[0]}" = gh ] || return
  [ "${CMD_ARGV[1]}" = pr ] || return
  [ "${CMD_ARGV[2]}" = merge ] || return
  echo "BLOCKED: Agents cannot merge PRs. Only the user merges PRs." >&2
  echo "Create the PR and report the URL to the user instead." >&2
  exit 2
}

_for_each_command _gm_check
exit 0
