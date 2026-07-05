#!/bin/bash
# Block interactive rebase and hunk-picker modes (require a TTY, not supported
# in Claude Code).
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no real git command. Flags are matched INSIDE a git command's ARGV
# only — a trailing `git checkout -b x && mkdir -p y` no longer cross-matches the
# `-p` of mkdir (audit A9 cross-matching class), because they are separate
# simple-commands with separate argv.
$NEEDS_GIT_CHECK || exit 0

_has_short() { case "$1" in --*) return 1 ;; -*"$2"*) return 0 ;; *) return 1 ;; esac; }

_ri_check() {
  [ "${CMD_ARGV[0]}" = git ] || return
  local sub="${CMD_ARGV[1]}" tok

  if [ "$sub" = rebase ]; then
    for tok in "${CMD_ARGV[@]:2}"; do
      if [ "$tok" = --interactive ] || _has_short "$tok" i; then
        echo "BLOCKED: Interactive rebase requires a terminal and is not supported in Claude Code." >&2
        echo "Use 'git rebase <branch>' (non-interactive) instead." >&2
        exit 2
      fi
    done
  fi

  # Interactive selection: -i/--interactive for add/stash.
  if [ "$sub" = add ] || [ "$sub" = stash ]; then
    for tok in "${CMD_ARGV[@]:2}"; do
      if [ "$tok" = --interactive ] || _has_short "$tok" i; then
        echo "BLOCKED: Interactive mode requires a terminal and is not supported in Claude Code." >&2
        exit 2
      fi
    done
  fi

  # Patch hunk selection: -p/--patch for add/stash/checkout/restore/reset.
  case "$sub" in
    add|stash|checkout|restore|reset)
      for tok in "${CMD_ARGV[@]:2}"; do
        if [ "$tok" = --patch ] || _has_short "$tok" p; then
          echo "BLOCKED: Patch mode (-p/--patch) requires a terminal and is not supported in Claude Code." >&2
          exit 2
        fi
      done ;;
  esac
}

_for_each_command _ri_check
exit 0
