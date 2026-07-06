#!/bin/bash
# PostToolUse advisory (NON-blocking): after a `git commit` or `git push`, report
# where the commit landed and LOUDLY flag ORPHANS — a fix that will never reach a
# deploy branch. Three orphan modes this catches automatically so Mike never has
# to question a fix by hand:
#   1. pushed to a branch whose PR is already MERGED (commit stranded off a dead
#      branch — the near-miss that prompted this hook),
#   2. pushed to a branch whose PR is CLOSED unmerged,
#   3. committed/pushed to a branch with NO PR (nothing carries it to deploy).
#
# It NEVER blocks — the git action already ran. It only surfaces status:
#   exit 0 + stdout  → OK / benign (a ✓ line, visible in transcript)
#   exit 2 + stderr  → LOUD alert fed back to the model so it fixes the orphan
# Scope (per Mike's choice): verify the commit is on an OPEN PR heading to merge,
# or — for a merged PR — that the merge actually INCLUDED this commit. Full
# staging→prod deploy-through is async and out of scope.
#
# Reuses the shared tokenizer (_parse-input.sh) so `cd repo && git push` and every
# wrapper/quote form resolve to the right git action + effective directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: not a git command at all → nothing to check (cheap, no gh/network).
# (Heredoc bodies are stripped upstream in _parse-input.sh, so a commit whose
# message body quotes git commands is not mis-read as those commands here.)
$NEEDS_GIT_CHECK || exit 0

# Find the git action this command performed. push wins over commit if both ran
# (a `git commit && git push` chain should be judged on the push).
ACTION=""; EFFDIR="."
_scan() {
  [ "${CMD_ARGV[0]}" = git ] || return
  case "${CMD_ARGV[1]}" in
    commit) [ "$ACTION" = push ] || { ACTION=commit; EFFDIR="$CMD_EFFDIR"; } ;;
    push)   ACTION=push; EFFDIR="$CMD_EFFDIR" ;;
  esac
}
_for_each_command _scan
[ -n "$ACTION" ] || exit 0

DIR=$(_resolve_dir "${EFFDIR:-.}")
cd "$DIR" 2>/dev/null || exit 0
command -v gh >/dev/null 2>&1 || exit 0     # no gh → can't check landing; stay silent

# This is a PostToolUse hook that must NEVER wedge a session, but it makes network
# calls (gh, git fetch). Cap each with a timeout so a hung remote/auth-prompt can't
# stall every commit. Stock macOS ships neither `timeout` nor `gtimeout`; perl IS a
# hard dependency of these hooks (_tokenize.pl), so fall back to its alarm(): fork
# the command and TERM it if it overruns. Portable, no coreutils required.
_to() { # _to <secs> <cmd...>
  local t="$1"; shift
  if   command -v timeout  >/dev/null 2>&1; then timeout  "$t" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$t" "$@"
  else
    perl -e '
      my $t = shift;
      my $pid = fork();
      if (!defined $pid) { exec @ARGV; exit 127; }      # fork failed → run un-timed (no regression)
      if ($pid == 0)     { exec @ARGV or exit 127; }    # child → the real command
      local $SIG{ALRM} = sub { kill "TERM", $pid; };
      alarm $t; waitpid($pid, 0); my $rc = $?; alarm 0;
      exit($rc & 127 ? 124 : ($rc >> 8));               # 124 = timed out (killed), else child rc
    ' "$t" "$@"
  fi
}

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -n "$BRANCH" ] && [ "$BRANCH" != HEAD ] || exit 0
HEAD_SHA=$(git rev-parse --short HEAD 2>/dev/null)

# Deploy branches aren't "fixes heading to a PR" — committing there is the git
# guards' concern, not this one. Only feature branches get orphan-checked.
case "$BRANCH" in main|master|staging) exit 0 ;; esac

# Most-recent PR for this branch, any state (one gh call; parsed with python3).
PR_JSON=$(_to 20 gh pr list --head "$BRANCH" --state all --json number,state,baseRefName,url --limit 1 2>/dev/null)
# A lookup FAILURE (timeout / auth / network — non-zero rc) is NOT the same as a
# successful empty result: without this guard an empty PR_JSON drops into the "no PR"
# path and cries a false orphan whenever GitHub is briefly unavailable. Stay silent
# on failure (fail-open); a successful `[]` still flows through as genuine "no PR".
[ $? -eq 0 ] || exit 0
PARSE=$(printf '%s' "$PR_JSON" | python3 -c '
import sys, json
try: a = json.load(sys.stdin)
except Exception: a = []
if a:
    p = a[0]
    print("\t".join((str(p["number"]), p["state"], p["baseRefName"], p["url"])))
' 2>/dev/null)
IFS=$'\t' read -r PR_NUM PR_STATE PR_BASE PR_URL <<< "$PARSE"

# --- No PR for this branch ---
if [ -z "$PR_NUM" ]; then
  if [ "$ACTION" = push ]; then
    echo "⚠️  fix-landing: pushed '$BRANCH' but it has NO open PR — nothing will carry $HEAD_SHA to a deploy branch. Open one: gh pr create." >&2
    exit 2
  fi
  exit 0    # a commit on a not-yet-PR'd branch is normal early work
fi

# After a push, git already updated the local origin/<branch> tracking ref, so no
# fetch is needed to know whether HEAD is on the remote branch.
ON_REMOTE=1; git merge-base --is-ancestor HEAD "origin/$BRANCH" 2>/dev/null || ON_REMOTE=0

case "$PR_STATE" in
  OPEN)
    if [ "$ON_REMOTE" = 1 ]; then
      echo "✓ fix-landing: $HEAD_SHA is on OPEN PR #$PR_NUM (→ $PR_BASE). $PR_URL"
      exit 0
    fi
    echo "ℹ️  fix-landing: committed $HEAD_SHA on '$BRANCH' (PR #$PR_NUM open) but it is NOT pushed yet — push so the fix reaches the PR." >&2
    exit 2 ;;
  MERGED)
    # Did the merge actually include HEAD? (the exact near-miss check)
    _to 20 git fetch -q origin "$PR_BASE" 2>/dev/null
    if git merge-base --is-ancestor HEAD "origin/$PR_BASE" 2>/dev/null; then
      echo "✓ fix-landing: $HEAD_SHA already in '$PR_BASE' via merged PR #$PR_NUM."
      exit 0
    fi
    echo "🚨 ORPHANED FIX: PR #$PR_NUM (branch '$BRANCH') is ALREADY MERGED, but $HEAD_SHA is NOT in '$PR_BASE' — this commit will NOT deploy. Open a NEW PR (branch off $PR_BASE, carry this commit) to land it. $PR_URL" >&2
    exit 2 ;;
  CLOSED)
    echo "🚨 fix-landing: PR #$PR_NUM (branch '$BRANCH') is CLOSED unmerged — commits here won't deploy. Reopen it or open a new PR. $PR_URL" >&2
    exit 2 ;;
esac
exit 0
