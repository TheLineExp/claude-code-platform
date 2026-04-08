#!/bin/bash
# Install git hooks and Claude Code platform hooks.
# Run once after cloning: bash hooks/install.sh
#
# Two installation methods:
#   1. Copy hooks to .git/hooks/ (default, works everywhere)
#   2. Set core.hooksPath to hooks/ (alternative, auto-updates)

set -e

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
  echo "ERROR: Not a git repository. Run this from inside a git repo."
  exit 1
fi

HOOKS_DIR="$REPO_ROOT/hooks"
GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "Installing Claude Code Development Platform hooks..."

# --- Method 1: Copy to .git/hooks/ ---
for hook in pre-commit pre-push; do
  if [ -f "$HOOKS_DIR/$hook" ]; then
    cp "$HOOKS_DIR/$hook" "$GIT_HOOKS_DIR/$hook"
    chmod +x "$GIT_HOOKS_DIR/$hook"
    echo "  [OK] Installed $hook"
  fi
done

# --- Ensure Claude Code hooks are executable ---
CLAUDE_HOOKS_DIR="$REPO_ROOT/.claude/hooks"
if [ -d "$CLAUDE_HOOKS_DIR" ]; then
  chmod +x "$CLAUDE_HOOKS_DIR"/*.sh 2>/dev/null || true
  echo "  [OK] Claude Code hooks made executable"
fi

# --- Ensure window-id sentinel exists ---
WINDOW_ID="$REPO_ROOT/.claude/window-id"
if [ ! -f "$WINDOW_ID" ]; then
  echo "setup" > "$WINDOW_ID"
  echo "  [OK] Created window-id sentinel"
fi

# --- Ensure active-work.md exists ---
ACTIVE_WORK="$REPO_ROOT/.claude/active-work.md"
if [ ! -f "$ACTIVE_WORK" ]; then
  cat > "$ACTIVE_WORK" << 'EOF'
| Window | Branch | Worktree Path | Area | Started |
|--------|--------|---------------|------|---------|
EOF
  echo "  [OK] Created active-work.md"
fi

# --- Ensure plans directory exists ---
mkdir -p "$REPO_ROOT/.claude/plans"

echo ""
echo "Installation complete!"
echo ""
echo "Hooks installed:"
echo "  Git:    pre-commit, pre-push"
echo "  Claude: $(ls "$CLAUDE_HOOKS_DIR"/*.sh 2>/dev/null | wc -l | tr -d ' ') Claude Code hooks"
echo ""
echo "Next steps:"
echo "  1. Review CLAUDE.md for project rules"
echo "  2. Run /letsbuild to start your first feature"
