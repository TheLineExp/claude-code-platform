#!/bin/bash
# Block Bash commands that write to files in the main repo via redirects.
# Catches: echo > file, cat > file, tee file, etc.
# This closes the bypass gap where enforce-worktree only catches Edit/Write tools.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no file redirect operators detected
$NEEDS_FILE_CHECK || exit 0

# Only enforce in the main repo (not in worktrees)
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
if echo "$GIT_DIR" | grep -q "/worktrees/"; then
  exit 0  # In a worktree, allow
fi

# Also allow if git-dir is just a file (worktree pointer)
if [ -f "$GIT_DIR" ] 2>/dev/null; then
  exit 0  # Worktree detected via .git file
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

# Does a write target land INSIDE the repo tree? Covers relative paths (with or
# without a leading `./`) and absolute paths under $REPO_ROOT. Explicitly allows
# /dev/*, .claude/ setup files, ~/… and $VAR targets, and paths that escape via `..`.
under_repo() {
  local t="${1%\"}"; t="${t#\"}"; t="${t%\'}"; t="${t#\'}"   # strip surrounding quotes
  case "$t" in
    /dev/*)               return 1 ;;   # device — allow
    .claude/*|*/.claude/*) return 1 ;;  # setup files — allow
    '~'*|'$'*)            return 1 ;;    # home/var expansion — not a repo-relative literal
    ../*|*/../*)          return 1 ;;    # escapes cwd — conservatively allow
    /*)                                  # absolute — block only if under the repo root
      [ -n "$REPO_ROOT" ] || return 1
      case "$t/" in "$REPO_ROOT/"*) return 0 ;; *) return 1 ;; esac ;;
    *)                   return 0 ;;     # plain relative → inside the repo
  esac
}

# Extract every redirect/tee target. Redirects: `>`/`>>` with or WITHOUT a space
# (`>f` and `> f`), excluding fd-dup forms (`>&`, `2>&1` — the char after `>` is `&`).
# tee: allow flags (`-a`, `--append`, …) before the filename.
TARGETS=$(
  # unquoted targets (stop at whitespace)
  echo "$COMMAND" | grep -oE '>>?[[:space:]]*[^[:space:]|&;<>"'"'"']+' | sed -E 's/^>>?[[:space:]]*//'
  echo "$COMMAND" | grep -oE '\btee([[:space:]]+-{1,2}[a-zA-Z-]+)*[[:space:]]+[^[:space:]|&;<>"'"'"']+' | sed -E 's/^tee([[:space:]]+-{1,2}[a-zA-Z-]+)*[[:space:]]+//'
  # quoted targets — REQUIRED for paths with spaces (the repo dir "Volo Technologies")
  echo "$COMMAND" | grep -oE '>>?[[:space:]]*"[^"]+"' | sed -E 's/^>>?[[:space:]]*//'
  echo "$COMMAND" | grep -oE ">>?[[:space:]]*'[^']+'" | sed -E "s/^>>?[[:space:]]*//"
  echo "$COMMAND" | grep -oE '\btee([[:space:]]+-{1,2}[a-zA-Z-]+)*[[:space:]]+"[^"]+"' | sed -E 's/^tee([[:space:]]+-{1,2}[a-zA-Z-]+)*[[:space:]]+//'
)

while IFS= read -r target; do
  [ -n "$target" ] || continue
  if under_repo "$target"; then
    echo "BLOCKED: Bash write to a repo file ('$target') detected in the main repo." >&2
    echo "Code modifications must happen in a worktree. Run /letsbuild first." >&2
    echo "(Writing to /tmp, /dev, ~/… or a path outside the repo is fine.)" >&2
    exit 2
  fi
done <<< "$TARGETS"

exit 0
