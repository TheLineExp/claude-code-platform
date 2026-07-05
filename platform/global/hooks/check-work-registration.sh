#!/bin/bash
# Verify the current branch is registered in active-work.md before committing.
# Searches both the current repo and the main repo (for worktree support).
# Warns about stale registrations (>7 days old).
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: only check on git commit (per segment — `cd wt && git commit`
# must still be seen; audit A1 class)
$NEEDS_GIT_CHECK || exit 0
echo "$GIT_SEGMENTS" | grep -qE '^git[[:space:]]+commit([[:space:]]|$)' || exit 0

# Global deployment: only enforce where the letsbuild workflow is active.
_fleet_active || exit 0

source "$SCRIPT_DIR/_config.sh"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Skip check for non-feature branches
if ! echo "$BRANCH" | grep -q "^${FEATURE_PREFIX}"; then
  exit 0
fi

# Collect candidate active-work files — the current repo AND (if in a worktree) the
# main checkout. The branch may be registered in EITHER (letsbuild copies the row into
# the worktree; one file can lag the other), so accept a match in any candidate rather
# than letting the main-repo file overwrite a valid worktree candidate.
CANDIDATES=()
[ -f "$REPO_ROOT/.claude/active-work.md" ] && CANDIDATES+=("$REPO_ROOT/.claude/active-work.md")
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null)
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  MAIN_REPO=$(dirname "$GIT_COMMON")
  [ -f "$MAIN_REPO/.claude/active-work.md" ] && CANDIDATES+=("$MAIN_REPO/.claude/active-work.md")
fi

if [ ${#CANDIDATES[@]} -eq 0 ]; then
  echo "BLOCKED: No .claude/active-work.md found. Run /letsbuild first to register your work." >&2
  exit 2
fi

# Registered = the branch is a WHOLE table column `| <branch> |`, not a substring, so
# `feature/w1-foo` is NOT satisfied by a row for `feature/w1-foobar`.
BRANCH_RE=$(printf '%s' "$BRANCH" | sed 's/[][\.*^$(){}+?|/]/\\&/g')
ACTIVE_WORK="${CANDIDATES[0]}"
REGISTERED=false
for f in "${CANDIDATES[@]}"; do
  if grep -qE "\|[[:space:]]*${BRANCH_RE}[[:space:]]*\|" "$f"; then
    REGISTERED=true; ACTIVE_WORK="$f"; break
  fi
done

# Check if branch is registered
if [ "$REGISTERED" != true ]; then
  echo "BLOCKED: Branch '$BRANCH' is not registered in active-work.md." >&2
  echo "" >&2
  echo "Current registrations:" >&2
  grep '^|' "$ACTIVE_WORK" | head -10 >&2
  echo "" >&2
  echo "Run /letsbuild to register your work, or add a row manually:" >&2
  echo "| wX | $BRANCH | ../worktree-path | area | $(date +%Y-%m-%d) |" >&2
  exit 2
fi

# Warn about stale registrations (>7 days old)
ENTRY_DATE=$(grep "$BRANCH" "$ACTIVE_WORK" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -1)
if [ -n "$ENTRY_DATE" ]; then
  # Cross-platform date calculation (works on macOS and Linux/Git Bash)
  ENTRY_EPOCH=$(date -d "$ENTRY_DATE" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$ENTRY_DATE" +%s 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s)
  if [ "$ENTRY_EPOCH" -gt 0 ] 2>/dev/null; then
    DAYS_OLD=$(( (NOW_EPOCH - ENTRY_EPOCH) / 86400 ))
    if [ "$DAYS_OLD" -gt 7 ]; then
      echo "WARNING: Registration for '$BRANCH' is $DAYS_OLD days old. Consider cleaning up if work is complete." >&2
    fi
  fi
fi

exit 0
