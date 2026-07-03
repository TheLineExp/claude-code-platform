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
if [[ -f "roster-events.jsonl" ]]; then
    echo "## Recent Events (last 20)"
    echo
    tail -20 roster-events.jsonl 2>/dev/null | while IFS= read -r line; do
        ts=$(echo "$line" | grep -oE '"ts":"[^"]*"' | cut -d'"' -f4)
        type=$(echo "$line" | grep -oE '"type":"[^"]*"' | cut -d'"' -f4)
        window=$(echo "$line" | grep -oE '"window":"[^"]*"' | cut -d'"' -f4)
        chunk=$(echo "$line" | grep -oE '"chunk":"[^"]*"' | cut -d'"' -f4)
        echo "- \`$ts\` $type | window=$window chunk=$chunk"
    done
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
