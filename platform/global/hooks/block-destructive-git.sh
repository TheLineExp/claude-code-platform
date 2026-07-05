#!/bin/bash
# Block destructive git operations: force push, forced (+) refspecs, hard reset,
# checkout/restore of the whole tree, clean --force.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no real git command. Matching walks ARGV TOKENS — a commit message
# or echo/grep argument that merely CONTAINS "--force" or "git reset --hard" is a
# single token this guard never inspects as a flag (audit A9).
$NEEDS_GIT_CHECK || exit 0

# A short cluster (single dash) containing <letter>, excluding long `--…` options.
_has_short() { case "$1" in --*) return 1 ;; -*"$2"*) return 0 ;; *) return 1 ;; esac; }

_dg_check() {
  [ "${CMD_ARGV[0]}" = git ] || return
  local sub="${CMD_ARGV[1]}" tok

  if [ "$sub" = push ]; then
    # Forced refspec (audit A4): `+HEAD:x` / `+branch` force-updates without any
    # --force flag — blocked regardless of --force-with-lease.
    for tok in "${CMD_ARGV[@]:2}"; do
      case "$tok" in -*) continue ;; +?*)
        echo "BLOCKED: forced refspec ('+...') force-updates the remote ref. Use a regular push or a new branch." >&2
        exit 2 ;; esac
    done
    # --force-with-lease is the safe variant (incl. prefixes / =value) — allow.
    for tok in "${CMD_ARGV[@]:2}"; do
      case "$tok" in --force-w*) return ;; esac
    done
    # Plain --force, or a -f short cluster.
    for tok in "${CMD_ARGV[@]:2}"; do
      if [ "$tok" = --force ] || _has_short "$tok" f; then
        echo "BLOCKED: Force push not allowed. Use --force-with-lease, a regular push, or a new branch." >&2
        exit 2
      fi
    done
  fi

  # reset --hard, incl. the unambiguous long-option prefixes git accepts (A5).
  if [ "$sub" = reset ]; then
    for tok in "${CMD_ARGV[@]:2}"; do
      case "$tok" in --h|--ha|--har|--hard)
        echo "BLOCKED: Hard reset not allowed. Use 'git stash' or 'git checkout <file>' for specific files." >&2
        exit 2 ;; esac
    done
  fi

  # checkout/restore of the WHOLE tree (audit A6): `.`, `./`, `..`, `../`, `-- .`,
  # the repo-root pathspec `:/`. A path that merely STARTS with a dot (.github/)
  # is a distinct token and does not match.
  if [ "$sub" = checkout ] || [ "$sub" = restore ]; then
    for tok in "${CMD_ARGV[@]:2}"; do
      case "$tok" in .|./|..|../|:/)
        echo "BLOCKED: checkout/restore of the whole tree discards all changes. Use 'git stash' instead." >&2
        exit 2 ;; esac
    done
  fi

  # git clean force — combined short flags (`-xdf`, `-df`) and --force.
  if [ "$sub" = clean ]; then
    for tok in "${CMD_ARGV[@]:2}"; do
      if [ "$tok" = --force ] || _has_short "$tok" f; then
        echo "BLOCKED: 'git clean' with force permanently deletes untracked files." >&2
        exit 2
      fi
    done
  fi
}

_for_each_command _dg_check
exit 0
