#!/usr/bin/env bash
# Regenerate roster.md from roster-events.jsonl + cross-check vs actual worktrees.
# Usage: roster.sh <project-dir>

set -uo pipefail

PROJECT_DIR="${1:-}"
if [[ -z "$PROJECT_DIR" || ! -d "$PROJECT_DIR" ]]; then
    echo "Usage: $0 <project-dir>" >&2
    exit 1
fi

cd "$PROJECT_DIR" || exit 1

EVENTS_FILE="roster-events.jsonl"
ROSTER_FILE="roster.md"
REPOS_FILE="repos.txt"

if [[ ! -f "$EVENTS_FILE" ]]; then
    echo "# Active Windows" > "$ROSTER_FILE"
    echo "" >> "$ROSTER_FILE"
    echo "_No events recorded yet._" >> "$ROSTER_FILE"
    cat "$ROSTER_FILE"
    exit 0
fi

# Build current state from events: window -> { branch, repo, worktree, chunk, opened_at, last_event_at }
declare -A WINDOW_STATE

while IFS= read -r line; do
    type=$(echo "$line" | grep -oE '"type":"[^"]*"' | cut -d'"' -f4)
    window=$(echo "$line" | grep -oE '"window":"[^"]*"' | cut -d'"' -f4)
    [[ -z "$window" ]] && continue

    case "$type" in
        window-opened)
            branch=$(echo "$line" | grep -oE '"branch":"[^"]*"' | cut -d'"' -f4)
            repo=$(echo "$line" | grep -oE '"repo":"[^"]*"' | cut -d'"' -f4)
            worktree=$(echo "$line" | grep -oE '"worktree":"[^"]*"' | cut -d'"' -f4)
            chunk=$(echo "$line" | grep -oE '"chunk":"[^"]*"' | cut -d'"' -f4)
            ts=$(echo "$line" | grep -oE '"ts":"[^"]*"' | cut -d'"' -f4)
            WINDOW_STATE[$window]="active|$branch|$repo|$worktree|$chunk|$ts|$ts"
            ;;
        chunk-assigned)
            chunk=$(echo "$line" | grep -oE '"chunk":"[^"]*"' | cut -d'"' -f4)
            ts=$(echo "$line" | grep -oE '"ts":"[^"]*"' | cut -d'"' -f4)
            if [[ -n "${WINDOW_STATE[$window]:-}" ]]; then
                IFS='|' read -r status br rp wt _ open_at _ <<< "${WINDOW_STATE[$window]}"
                WINDOW_STATE[$window]="$status|$br|$rp|$wt|$chunk|$open_at|$ts"
            fi
            ;;
        window-closed)
            unset "WINDOW_STATE[$window]"
            ;;
        chunk-merged|chunk-shipped|blocker)
            ts=$(echo "$line" | grep -oE '"ts":"[^"]*"' | cut -d'"' -f4)
            if [[ -n "${WINDOW_STATE[$window]:-}" ]]; then
                IFS='|' read -r status br rp wt ck open_at _ <<< "${WINDOW_STATE[$window]}"
                WINDOW_STATE[$window]="$status|$br|$rp|$wt|$ck|$open_at|$ts"
            fi
            ;;
    esac
done < "$EVENTS_FILE"

# Render
{
    echo "# Active Windows"
    echo
    echo "_Regenerated from \`roster-events.jsonl\` at $(date -u +%Y-%m-%dT%H:%M:%SZ). Do not edit by hand — append events instead._"
    echo
    echo "| Window | Branch | Repo | Worktree | Current Chunk | Opened | Last Activity |"
    echo "|---|---|---|---|---|---|---|"

    for window in "${!WINDOW_STATE[@]}"; do
        IFS='|' read -r status br rp wt ck open_at last_at <<< "${WINDOW_STATE[$window]}"
        echo "| $window | \`$br\` | $rp | \`$wt\` | $ck | $open_at | $last_at |"
    done
} > "$ROSTER_FILE"

cat "$ROSTER_FILE"

# Orphan / ghost detection if repos.txt available
if [[ -f "$REPOS_FILE" ]]; then
    echo
    echo "## Cross-check vs git worktrees"
    echo
    while IFS= read -r repo; do
        [[ -z "$repo" || "$repo" =~ ^# ]] && continue
        [[ ! -d "$repo/.git" ]] && continue
        echo "### $(basename "$repo")"
        echo
        wt_list=$(cd "$repo" && git worktree list 2>/dev/null)
        echo "\`\`\`"
        echo "$wt_list"
        echo "\`\`\`"
        echo
    done < "$REPOS_FILE"
fi
