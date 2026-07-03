#!/usr/bin/env bash
# Multi-repo audit. Usage: sweep.sh <repos-file>
# Outputs structured markdown to stdout.

set -uo pipefail

REPOS_FILE="${1:-}"
if [[ -z "$REPOS_FILE" || ! -f "$REPOS_FILE" ]]; then
    echo "Usage: $0 <repos-file>" >&2
    echo "  repos-file format: one repo path per line, comments with #" >&2
    exit 1
fi

echo "# Multi-repo sweep — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

while IFS= read -r repo; do
    [[ -z "$repo" || "$repo" =~ ^# ]] && continue
    [[ ! -d "$repo/.git" ]] && { echo "## $repo"; echo "- ❌ not a git repository"; echo; continue; }

    repo_name=$(basename "$repo")
    echo "## $repo_name (\`$repo\`)"
    echo

    cd "$repo" || { echo "- ❌ cd failed"; echo; continue; }

    # Current branch + status
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    echo "**Branch**: \`$branch\`"

    # Ahead/behind origin
    git fetch origin --quiet 2>/dev/null || true
    if git rev-parse "origin/$branch" >/dev/null 2>&1; then
        counts=$(git rev-list --left-right --count "origin/$branch...HEAD" 2>/dev/null || echo "? ?")
        behind=$(echo "$counts" | awk '{print $1}')
        ahead=$(echo "$counts" | awk '{print $2}')
        echo "**Ahead/behind origin**: $ahead ahead, $behind behind"
    fi

    # Uncommitted state
    dirty=$(git status --porcelain 2>/dev/null | wc -l)
    if [[ "$dirty" -gt 0 ]]; then
        echo "**⚠️ Uncommitted changes**: $dirty file(s)"
        git status --short 2>/dev/null | head -10 | sed 's/^/    /'
        if [[ "$dirty" -gt 10 ]]; then echo "    ... and $((dirty - 10)) more"; fi
    fi

    # Worktrees
    echo
    echo "**Worktrees**:"
    git worktree list 2>/dev/null | sed 's/^/- `/' | sed 's/$/`/'

    # Worktree directories on disk vs registry
    parent_dir=$(dirname "$repo")
    on_disk=$(find "$parent_dir" -maxdepth 1 -type d -name "${repo_name}-*" 2>/dev/null | sort)
    registered=$(git worktree list --porcelain 2>/dev/null | grep "^worktree " | awk '{print $2}' | sort)
    orphans=$(comm -23 <(echo "$on_disk") <(echo "$registered") 2>/dev/null)
    if [[ -n "$orphans" ]]; then
        echo
        echo "**🚨 Orphan worktree directories (on disk, not in git registry)**:"
        echo "$orphans" | sed 's/^/- `/' | sed 's/$/`/'
    fi

    # Active-work registry rows vs actual worktrees
    if [[ -f ".claude/active-work.md" ]]; then
        registry_rows=$(grep -E '^\| (w[0-9]+|x[0-9]+|s|mk|bot)' .claude/active-work.md 2>/dev/null | wc -l)
        echo
        echo "**Active-work.md rows**: $registry_rows"
    fi

    # Open PRs
    if command -v gh >/dev/null 2>&1; then
        echo
        remote_url=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ -n "$remote_url" ]]; then
            slug=$(echo "$remote_url" | sed -E 's|.*github.com[:/]([^/]+/[^/]+)(\.git)?$|\1|' | sed 's/\.git$//')
            pr_count=$(gh pr list --repo "$slug" --state open --limit 100 --json number 2>/dev/null | grep -c "number" || echo "0")
            dependabot_count=$(gh pr list --repo "$slug" --state open --limit 100 --search "author:app/dependabot" --json number 2>/dev/null | grep -c "number" || echo "0")
            feature_count=$((pr_count - dependabot_count))
            echo "**Open PRs**: $pr_count total ($feature_count feature, $dependabot_count dependabot)"
        fi
    fi

    # Stale merged-but-not-deleted branches
    echo
    merged_branches=$(git branch --merged "origin/$branch" 2>/dev/null | grep -v "^\*" | grep -v "^  $branch$" | grep -v "^  master$" | grep -v "^  main$" | grep "^  feature/" | head -10)
    if [[ -n "$merged_branches" ]]; then
        echo "**Merged-but-undeleted local branches** (cleanup candidates):"
        echo "$merged_branches" | sed 's/^  /- `/' | sed 's/$/`/'
    fi

    echo
    echo "---"
    echo
done < "$REPOS_FILE"

echo
echo "## Recommended actions"
echo
echo "Review the orphans, dirty main repos, and merged-but-undeleted branches above. Use \`/pm\` subcommands or manual git ops to clean. Never delete unmerged branches without confirming merge state via \`gh pr view\`."
