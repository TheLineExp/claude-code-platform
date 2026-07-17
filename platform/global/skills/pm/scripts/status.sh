#!/usr/bin/env bash
# Status roll-up: read project state files + GH PR data, emit a markdown summary.
# Usage: status.sh <project-dir>

set -uo pipefail

PROJECT_DIR="${1:-}"
if [[ -z "$PROJECT_DIR" || ! -d "$PROJECT_DIR" ]]; then
    echo "Usage: $0 <project-dir>" >&2
    exit 1
fi

cd "$PROJECT_DIR" || exit 1

PROJECT_NAME=$(basename "$PROJECT_DIR")
DATE=$(date -u +%Y-%m-%d)
TIME=$(date -u +%H:%M:%SZ)

echo "# $PROJECT_NAME — Status Report ($DATE $TIME)"
echo

# Status table per chunk
if [[ -f "status.md" ]]; then
    echo "## Chunks"
    echo
    cat status.md
    echo
fi

# Active windows from roster
if [[ -f "roster.md" ]]; then
    echo "## Active Windows"
    echo
    cat roster.md
    echo
fi

# Recent events
# NOTE: the event-kind key is `event`, NOT `type`. This grepped "type" and silently
# rendered every event as blank/? since inception. Use jq — the rows carry free-text
# notes with quotes and braces that regex-scraping mangles.
if [[ -f "roster-events.jsonl" ]]; then
    echo "## Recent Events (last 20)"
    echo
    if command -v jq >/dev/null 2>&1; then
        tail -20 roster-events.jsonl 2>/dev/null | jq -r '
            # .pr is polymorphic: number, qualified string ("org/repo#1299"), or array.
            def prfmt: if type == "array" then (map(tostring) | join(", "))
                       elif type == "number" then "#\(.)"
                       else tostring end;
            # timestamp key is `ts` on most rows, `date` on ~194 others (both used).
            "- `\(.ts // .date // "?")` \(.event // "?")"
            + " | window=\(.window // "-")"
            + " | chunk=\(.chunk // "-")"
            + (if .pr      then " | pr=\(.pr | prfmt)"   else "" end)
            + (if .verdict then " | verdict=\(.verdict)" else "" end)
        ' 2>/dev/null || tail -20 roster-events.jsonl
    else
        tail -20 roster-events.jsonl
    fi
    echo
fi

# Pending decisions
if [[ -d "decisions" ]]; then
    pending=$(grep -L "Decision: \(.*\)" decisions/*.md 2>/dev/null | wc -l)
    answered=$(grep -l "Decision: \(.*\)" decisions/*.md 2>/dev/null | wc -l)
    echo "## Decisions"
    echo
    echo "- Open (unanswered): $pending"
    echo "- Answered: $answered"
    if [[ $pending -gt 0 ]]; then
        echo
        echo "**Pending decisions**:"
        for f in decisions/*.md; do
            [[ -f "$f" ]] || continue
            if ! grep -q "Decision: \(.*\)" "$f" 2>/dev/null; then
                echo "- \`$(basename "$f")\`"
            fi
        done
    fi
    echo
fi

# Pending acceptance reviews
if [[ -f "acceptance-log.md" ]]; then
    pending_acc=$(grep -c "Status.*pending" acceptance-log.md 2>/dev/null || echo "0")
    echo "## Acceptance"
    echo
    echo "- Pending review: $pending_acc"
    echo
fi

# Latest milestone review status
if [[ -d "reviews" ]]; then
    latest=$(ls -t reviews/milestone-*-code-review.md 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
        critical=$(grep -ci "critical" "$latest" 2>/dev/null || echo "0")
        warning=$(grep -ci "warning" "$latest" 2>/dev/null || echo "0")
        echo "## Latest Milestone Review"
        echo
        echo "- File: \`$(basename "$latest")\`"
        echo "- Critical findings: $critical"
        echo "- Warnings: $warning"
        echo
    fi
fi
