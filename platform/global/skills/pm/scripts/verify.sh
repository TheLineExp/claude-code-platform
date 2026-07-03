#!/usr/bin/env bash
# Verify a PR has merged on origin/staging (or origin/main/master per repo convention).
# Usage: verify.sh <pr-number> <repo-path>
# Outputs JSON-like structured result to stdout.

set -uo pipefail

PR_NUMBER="${1:-}"
REPO_PATH="${2:-}"

if [[ -z "$PR_NUMBER" || -z "$REPO_PATH" ]]; then
    echo "Usage: $0 <pr-number> <repo-path>" >&2
    exit 1
fi

cd "$REPO_PATH" || { echo "{\"error\": \"cd failed\"}"; exit 1; }

# Fetch latest
git fetch origin --quiet 2>/dev/null || true

# Determine production-equivalent branch (master vs main vs staging)
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
slug=$(echo "$remote_url" | sed -E 's|.*github.com[:/]([^/]+/[^/]+)(\.git)?$|\1|' | sed 's/\.git$//')

if ! command -v gh >/dev/null 2>&1; then
    echo "{\"error\": \"gh CLI not available\"}"
    exit 1
fi

pr_data=$(gh pr view "$PR_NUMBER" --repo "$slug" --json state,mergedAt,baseRefName,title,url,mergeCommit 2>/dev/null)
if [[ -z "$pr_data" ]]; then
    echo "{\"error\": \"PR #$PR_NUMBER not found in $slug\"}"
    exit 1
fi

state=$(echo "$pr_data" | grep -oE '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
merged_at=$(echo "$pr_data" | grep -oE '"mergedAt":"[^"]*"' | head -1 | cut -d'"' -f4)
base=$(echo "$pr_data" | grep -oE '"baseRefName":"[^"]*"' | head -1 | cut -d'"' -f4)
title=$(echo "$pr_data" | grep -oE '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
url=$(echo "$pr_data" | grep -oE '"url":"[^"]*"' | head -1 | cut -d'"' -f4)
merge_commit=$(echo "$pr_data" | grep -oE '"oid":"[^"]*"' | head -1 | cut -d'"' -f4)

# Confirm merge commit appears on origin/<base>
on_branch="false"
if [[ -n "$merge_commit" ]]; then
    if git merge-base --is-ancestor "$merge_commit" "origin/$base" 2>/dev/null; then
        on_branch="true"
    fi
fi

# Output structured result
cat <<EOF
{
  "repo": "$slug",
  "pr_number": $PR_NUMBER,
  "title": "$title",
  "state": "$state",
  "base_branch": "$base",
  "merged_at": "$merged_at",
  "merge_commit_on_base": $on_branch,
  "merge_commit": "$merge_commit",
  "url": "$url"
}
EOF
