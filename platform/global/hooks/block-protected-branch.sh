#!/bin/bash
# Block git commits/pushes/merges that write to protected deploy branches.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no real git command (audit A1: `cd wt && git push`, `VAR=1 git push`,
# `true; git push` are all real git commands in the argv model — no `^git` anchor).
$NEEDS_GIT_CHECK || exit 0
source "$SCRIPT_DIR/_config.sh"

# Each command carries its effective directory (CMD_EFFDIR — `git -C <path>`,
# `cd <path> &&`, `--git-dir`/`--work-tree`; PR #11 R4/R5/R7). Branch identity and
# fleet-shape are resolved AT that directory, so `git -C ../main commit` from a
# feature worktree is judged by ../main's branch. "Protected" means the fleet's
# PR-based deploy branches — a personal trunk repo (no .claude/) legitimately
# commits to main, so each command self-gates on _fleet_shaped at its effdir,
# failing CLOSED even when active-work.md is emptied (audit A8).
_pb_check() {
  [ "${CMD_ARGV[0]}" = git ] || return
  local sub="${CMD_ARGV[1]}" effdir branch tok dst p
  case "$sub" in commit|push|merge) ;; *) return ;; esac

  effdir=$(_resolve_dir "${CMD_EFFDIR:-.}")
  _fleet_shaped "$effdir" || return
  # A config/data trunk repo (e.g. the dev-system + backlog repo) is .claude/-shaped
  # but is NOT a product deploy target — direct push/commit to its main is the
  # intended workflow (the /feature + /todo skills commit && push to main). Exempt
  # it from deploy-branch protection; product repos are never in $TRUNK_REPOS.
  _is_trunk_repo "$effdir" && return
  branch=$(git -C "$effdir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)

  # Refspec check (push): a push can target a protected branch from ANY branch —
  # `git push origin master`, `HEAD:staging`, fully-qualified `HEAD:refs/heads/…`
  # (audit A3), forced `+master` (A4), glob `refs/heads/*` (PR #11 R1). The dst of
  # each non-flag operand is the part after the last `:`, minus a leading `+` and
  # `refs/heads/` — so `feature/staging-fix` does NOT false-positive.
  if [ "$sub" = push ]; then
    for tok in "${CMD_ARGV[@]:2}"; do
      case "$tok" in -*) continue ;; esac
      case "$tok" in
        *\**)
          echo "BLOCKED: glob refspec on push can write protected branches. Push explicit branch names." >&2
          exit 2 ;;
      esac
      dst="${tok##*:}"; dst="${dst#+}"; dst="${dst#refs/heads/}"
      for p in $PROTECTED_BRANCHES; do
        if [ "$dst" = "$p" ]; then
          echo "BLOCKED: push targets a protected branch (refspec → $p)." >&2
          echo "  Protected branches deploy via PR, not a direct push. Use 'gh pr create'." >&2
          exit 2
        fi
      done
    done
  fi

  # Block commits AND pushes/merges while STANDING on a protected branch (a bare
  # `git push`/`git commit` names nothing, so gate on the effective branch).
  for p in $PROTECTED_BRANCHES; do
    [ "$branch" = "$p" ] || continue
    case "$sub" in
      commit)
        echo "BLOCKED: Cannot commit on '$branch'. Create a feature branch first." >&2
        echo "  git checkout -b ${FEATURE_PREFIX}your-description" >&2
        exit 2 ;;
      merge)
        echo "BLOCKED: Cannot 'git merge' while on protected branch '$branch' — that writes direct" >&2
        echo "  protected-branch history. Promote via PR instead." >&2
        exit 2 ;;
      push)
        echo "BLOCKED: Cannot 'git push' while on protected branch '$branch'." >&2
        echo "  Protected branches deploy via PR, not a direct push." >&2
        echo "  Switch to your feature branch, or open a PR with 'gh pr create'." >&2
        exit 2 ;;
    esac
  done
}

_for_each_command _pb_check
exit 0
