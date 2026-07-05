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

source "$SCRIPT_DIR/_config.sh"
PROT_ALT=$(echo "$PROTECTED_BRANCHES" | tr ' ' '|' | sed 's/|$//')

# Each line is `EFFDIR<TAB>SEGMENT` — EFFDIR is the checkout the command writes
# (`git -C <path> …`; PR #11 R4). Branch identity and fleet-shape are resolved AT
# that directory, so `git -C ../main commit` from a feature worktree is judged by
# ../main's branch, not the worktree's. Deployed globally, but "protected" means
# the fleet's PR-based deploy branches — a personal trunk repo (no .claude/)
# legitimately commits to main, so each segment self-gates on _fleet_shaped at
# its EFFDIR, failing CLOSED even when active-work.md is emptied (audit A8).
while IFS=$'\t' read -r effdir seg; do
  [ -n "$seg" ] || continue
  echo "$seg" | grep -qE '^git[[:space:]]+(commit|push|merge)([[:space:]]|$)' || continue
  effdir=$(_resolve_dir "${effdir:-.}")
  _fleet_shaped "$effdir" || continue

  BRANCH=$(git -C "$effdir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

  # Refspec check (push): a push can target a protected branch from ANY checked-out
  # branch — `git push origin HEAD:staging`, `git push origin feat:master`,
  # `git push origin master`, the fully-qualified `HEAD:refs/heads/staging`
  # (audit A3), forced `+master`, and glob `refs/heads/*` (PR #11 R1) refspecs.
  # Match a protected name at a refspec boundary (preceded by `:` or space, opt.
  # `+`/`refs/heads/`) so `feature/staging-fix` does NOT false-positive.
  if echo "$seg" | grep -qE '^git[[:space:]]+push([[:space:]]|$)'; then
    if [ -n "$PROT_ALT" ] && echo "$seg" | grep -qE "(:|[[:space:]])\\+?(refs/heads/)?(${PROT_ALT})([[:space:]]|\$)"; then
      echo "BLOCKED: push targets a protected branch (refspec → ${PROT_ALT})." >&2
      echo "  Protected branches deploy via PR, not a direct push. Use 'gh pr create'." >&2
      exit 2
    fi
    if echo "$seg" | grep -qE '(^|[[:space:]])[^-[:space:]][^[:space:]]*\*'; then
      echo "BLOCKED: glob refspec on push can write protected branches. Push explicit branch names." >&2
      exit 2
    fi
  fi

  # Block commits AND pushes while STANDING on a protected branch. A bare
  # `git push`/`git commit` names nothing, so gate on the effective branch.
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
done <<< "$GIT_SEGMENTS_D"

exit 0
