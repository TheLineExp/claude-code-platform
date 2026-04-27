#!/usr/bin/env bash
# Post-merge hook: when a PR merges to staging, append a chunk-merged event
# to the active project's roster-events.jsonl. Optional — best paired with a
# GitHub Actions workflow that calls this on `staging` push events.
#
# Usage (from a GH Action):
#   bash post-merge-status.sh <project> <chunk-id> <pr-number> <repo-slug> <merge-commit>
#
# The workflow needs to know the chunk-id; conventionally the PR title or
# branch name encodes it (e.g. feature/w1-P5-foo → chunk P5).

set -uo pipefail

PROJECT="${1:-}"
CHUNK="${2:-}"
PR="${3:-}"
REPO="${4:-}"
COMMIT="${5:-}"

if [[ -z "$PROJECT" || -z "$CHUNK" || -z "$PR" ]]; then
    echo "Usage: $0 <project> <chunk-id> <pr-number> [<repo-slug>] [<merge-commit>]" >&2
    exit 1
fi

PROJECT_DIR="$HOME/.claude/pm/$PROJECT"
[[ ! -d "$PROJECT_DIR" ]] && { echo "Project dir not found: $PROJECT_DIR" >&2; exit 1; }

EVENTS_FILE="$PROJECT_DIR/roster-events.jsonl"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat >> "$EVENTS_FILE" <<EOF
{"ts":"$TS","type":"chunk-merged","chunk":"$CHUNK","pr":"$PR","repo":"$REPO","commit":"$COMMIT"}
EOF

echo "Recorded: $CHUNK merged at #$PR ($REPO) at $TS"

# Update status.md if it exists
STATUS_FILE="$PROJECT_DIR/status.md"
if [[ -f "$STATUS_FILE" ]]; then
    # naive in-place: append a merged-line if pattern not already there
    if ! grep -q "$CHUNK.*merged" "$STATUS_FILE"; then
        echo "- $CHUNK: merged at #$PR on $TS" >> "$STATUS_FILE"
    fi
fi
