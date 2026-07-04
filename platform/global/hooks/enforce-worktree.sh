#!/bin/bash
# Block code modifications in the main repo. Agents must work in worktrees.
# Checks the FILE PATH being edited, not the CWD — so edits to worktree files
# and other repos are always allowed.
# Allows: .claude/ file edits (for setup), files outside the main repo, Bash commands
# Exit 2 = block, Exit 0 = allow

INPUT=$(cat)

# Extract file_path from the tool input JSON
FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# No file_path means this is a Bash command — let other hooks handle those
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Get the MAIN checkout's absolute path. NOT --show-toplevel: in a linked
# worktree that returns the worktree root, so files inside the worktree would
# look like they're "in the main repo" and get wrongly blocked. --git-common-dir
# always resolves to the main repo's .git, whose parent is the main checkout.
COMMON=$(git rev-parse --git-common-dir 2>/dev/null)
if [ -z "$COMMON" ]; then
  exit 0
fi
case "$COMMON" in
  /*) ;;                        # already absolute
  *) COMMON="$(pwd)/$COMMON" ;; # relative (e.g. ".git" from the main root)
esac
MAIN_REPO=$(cd "$(dirname "$COMMON")" 2>/dev/null && pwd)
if [ -z "$MAIN_REPO" ]; then
  exit 0
fi

# Deployed globally — but worktree discipline only applies where the letsbuild workflow
# is set up, signalled by a registered row in the main repo's active-work.md. Repos with
# no registered work (the platform repo, one-off checkouts) are edited directly → no-op.
if [ ! -f "$MAIN_REPO/.claude/active-work.md" ] || \
   ! grep -qE '^\|[[:space:]]*(w|x|s)[0-9]*[[:space:]]*\|' "$MAIN_REPO/.claude/active-work.md" 2>/dev/null; then
  exit 0
fi

# Normalize paths for comparison (Windows paths vs MSYS paths)
normalize() {
  local p="$1"
  # Convert backslashes to forward slashes
  p="${p//\\//}"
  # Convert C:/... to /c/... (MSYS-style)
  if [[ "$p" =~ ^([a-zA-Z]):/ ]]; then
    local drive="${BASH_REMATCH[1]}"
    drive=$(echo "$drive" | tr 'A-Z' 'a-z')
    p="/$drive${p:2}"
  fi
  # Remove trailing slash
  p="${p%/}"
  echo "$p"
}

NORM_REPO=$(normalize "$MAIN_REPO")
NORM_FILE=$(normalize "$FILE_PATH")

# If the file is NOT inside the main repo, allow it
# (covers worktree dirs, other repos, etc.)
if [[ "$NORM_FILE" != "$NORM_REPO"/* ]]; then
  exit 0
fi

# File IS inside the main repo — allow .claude/ edits (setup, hooks, skills)
if echo "$NORM_FILE" | grep -qi '/\.claude/'; then
  exit 0
fi

# Solo mode bypass — when only one agent is active, no worktree needed
WINDOW_ID_FILE="$NORM_REPO/.claude/window-id"
if [ -f "$WINDOW_ID_FILE" ]; then
  WID=$(cat "$WINDOW_ID_FILE" | tr -d '[:space:]')
  if [ "$WID" = "s" ]; then
    exit 0
  fi
fi

# Block all other file edits in the main repo
echo "BLOCKED: File is inside the main repo (not a worktree)." >&2
echo "" >&2
echo "Code edits must happen in your worktree directory." >&2
echo "Run /letsbuild first to create your worktree, then open Claude Code at that path." >&2
exit 2
