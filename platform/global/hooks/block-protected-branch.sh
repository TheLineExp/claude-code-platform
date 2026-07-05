#!/bin/bash
# Block git commits/pushes/merges that write to protected deploy branches.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no real git command segment (audit A1: `cd wt && git push`,
# `VAR=1 git push`, `true; git push` must all reach the checks below — matching
# happens per SEGMENT, never against the raw command).
$NEEDS_GIT_CHECK || exit 0
echo "$GIT_SEGMENTS" | grep -qE '^git[[:space:]]+(commit|push|merge)([[:space:]]|$)' || exit 0

# Deployed globally, but "protected branches" means the fleet's PR-based DEPLOY
# branches (staging/master/main). A personal trunk-based repo (no .claude/)
# legitimately commits to main. Gate on the repo being fleet-SHAPED — fail
# CLOSED even when active-work.md is emptied or corrupted (audit A8).
_fleet_shaped || exit 0

source "$SCRIPT_DIR/_config.sh"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
PROT_ALT=$(echo "$PROTECTED_BRANCHES" | tr ' ' '|' | sed 's/|$//')

while IFS= read -r seg; do
  [ -n "$seg" ] || continue

  # Refspec check: a push can target a protected branch from ANY checked-out
  # branch — `git push origin HEAD:staging`, `git push origin feat:master`,
  # `git push origin master`, and (audit A3) the fully-qualified form
  # `HEAD:refs/heads/staging` plus forced `+master` refspecs. Match a protected
  # name at a refspec boundary: preceded by `:`, space (optionally `+` and/or
  # `refs/heads/`), followed by space/end — so `feature/staging-fix` (staging
  # after an ordinary `/`) does NOT false-positive.
  if echo "$seg" | grep -qE '^git[[:space:]]+push([[:space:]]|$)'; then
    if [ -n "$PROT_ALT" ] && echo "$seg" | grep -qE "(:|[[:space:]])\\+?(refs/heads/)?(${PROT_ALT})([[:space:]]|\$)"; then
      echo "BLOCKED: push targets a protected branch (refspec → ${PROT_ALT})." >&2
      echo "  Protected branches deploy via PR, not a direct push. Use 'gh pr create'." >&2
      exit 2
    fi
    # Glob refspecs (`refs/heads/*`, `x*:x*`) can update protected branches
    # without ever naming them — block any non-flag push argument containing `*`.
    if echo "$seg" | grep -qE '(^|[[:space:]])[^-[:space:]][^[:space:]]*\*'; then
      echo "BLOCKED: glob refspec on push can write protected branches. Push explicit branch names." >&2
      exit 2
    fi
  fi

  # Block commits AND pushes while STANDING on a protected branch. The command
  # text alone is not enough — a bare `git push` (or `git commit`) on a
  # checked-out protected branch names nothing, so gate on the CURRENT branch.
  for protected in $PROTECTED_BRANCHES; do
    if [ "$BRANCH" = "$protected" ]; then
      if echo "$seg" | grep -qE '^git[[:space:]]+commit([[:space:]]|$)'; then
        echo "BLOCKED: Cannot commit on '$BRANCH'. Create a feature branch first." >&2
        echo "  git checkout -b ${FEATURE_PREFIX}your-description" >&2
        exit 2
      elif echo "$seg" | grep -qE '^git[[:space:]]+merge([[:space:]]|$)'; then
        echo "BLOCKED: Cannot 'git merge' while on protected branch '$BRANCH' — that writes direct" >&2
        echo "  protected-branch history. Promote via PR instead." >&2
        exit 2
      elif echo "$seg" | grep -qE '^git[[:space:]]+push([[:space:]]|$)'; then
        echo "BLOCKED: Cannot 'git push' while on protected branch '$BRANCH'." >&2
        echo "  Protected branches deploy via PR, not a direct push." >&2
        echo "  Switch to your feature branch, or open a PR with 'gh pr create'." >&2
        exit 2
      fi
    fi
  done
done <<< "$GIT_SEGMENTS"

exit 0
