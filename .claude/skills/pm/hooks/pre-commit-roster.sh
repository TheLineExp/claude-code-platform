#!/usr/bin/env bash
# Pre-commit hook for product repos: validates .claude/active-work.md format.
# Install: copy to <repo>/.git/hooks/pre-commit (chmod +x).
# Or symlink from a hooks/ dir installed by your repo's hooks/install.sh.

set -uo pipefail

ACTIVE_WORK=".claude/active-work.md"
[[ ! -f "$ACTIVE_WORK" ]] && exit 0

# Skip if file is unchanged
if ! git diff --cached --name-only 2>/dev/null | grep -q "^$ACTIVE_WORK$"; then
    exit 0
fi

# Pull staged content
staged=$(git show ":$ACTIVE_WORK" 2>/dev/null || echo "")
[[ -z "$staged" ]] && exit 0

# Validate: every data row must match the table format
errors=0

while IFS= read -r line; do
    # Skip header, separator, blank lines, comments, prose
    [[ "$line" =~ ^# ]] && continue
    [[ "$line" =~ ^\| *Window ]] && continue
    [[ "$line" =~ ^\|[-: ]+\| ]] && continue
    [[ -z "${line// }" ]] && continue
    [[ ! "$line" =~ ^\| ]] && continue

    # Data row: must have 5 pipes (Window, Branch, Worktree, Area, Started)
    pipes=$(echo "$line" | tr -cd '|' | wc -c)
    if [[ "$pipes" -lt 5 ]]; then
        echo "❌ active-work.md row has too few columns: $line" >&2
        errors=$((errors + 1))
    fi

    # Window column must be valid format: w1-w9, x1-x9, mk, bot, s
    window=$(echo "$line" | awk -F'|' '{print $2}' | tr -d ' ')
    if [[ -n "$window" ]] && ! [[ "$window" =~ ^(w[0-9]+|x[0-9]+|mk|bot|s|setup)$ ]]; then
        echo "❌ active-work.md invalid window-id: '$window' (must be w[0-9]+, x[0-9]+, mk, bot, s, or setup)" >&2
        errors=$((errors + 1))
    fi
done <<< "$staged"

# Check for duplicate window IDs (only among non-merged active rows)
dupes=$(echo "$staged" | grep -E '^\| (w[0-9]+|x[0-9]+|s)' | awk -F'|' '{print $2}' | tr -d ' ' | sort | uniq -d)
if [[ -n "$dupes" ]]; then
    echo "❌ active-work.md has duplicate window-id(s):" >&2
    echo "$dupes" | sed 's/^/  - /' >&2
    errors=$((errors + 1))
fi

if [[ "$errors" -gt 0 ]]; then
    echo >&2
    echo "$errors error(s) found in $ACTIVE_WORK." >&2
    echo "Fix the file (or remove from staging) and commit again." >&2
    exit 1
fi

exit 0
