#!/usr/bin/env bash
# Install git hooks for the current repository.
# Run once after cloning: bash hooks/install.sh
#
# Copies pre-commit and pre-push from hooks/ into .git/hooks/,
# makes Claude Code guard-hook scripts executable, and ensures
# the active-work sentinel files exist.
#
# macOS / Linux only.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: Not a git repository.  Run this from inside a cloned repo." >&2
  exit 1
}

HOOKS_DIR="$REPO_ROOT/hooks"
GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"
CLAUDE_HOOKS_DIR="$REPO_ROOT/.claude/hooks"

echo "Installing Claude Code Development Platform hooks..."

# ── git hooks (pre-commit, pre-push) ─────────────────────────────────────────
for hook in pre-commit pre-push; do
  if [ -f "$HOOKS_DIR/$hook" ]; then
    cp "$HOOKS_DIR/$hook" "$GIT_HOOKS_DIR/$hook"
    chmod +x "$GIT_HOOKS_DIR/$hook"
    echo "  [OK] Installed git hook: $hook"
  fi
done

# ── Claude Code guard hooks: ensure executable ────────────────────────────────
if [ -d "$CLAUDE_HOOKS_DIR" ]; then
  while IFS= read -r -d '' f; do
    chmod +x "$f"
  done < <(find "$CLAUDE_HOOKS_DIR" -maxdepth 1 -name "*.sh" -print0 2>/dev/null)
  echo "  [OK] Claude Code hooks made executable"
fi

# ── window-id sentinel ────────────────────────────────────────────────────────
WINDOW_ID="$REPO_ROOT/.claude/window-id"
if [ ! -f "$WINDOW_ID" ]; then
  mkdir -p "$(dirname "$WINDOW_ID")"
  echo "setup" > "$WINDOW_ID"
  echo "  [OK] Created window-id sentinel"
fi

# ── active-work registry ──────────────────────────────────────────────────────
ACTIVE_WORK="$REPO_ROOT/.claude/active-work.md"
if [ ! -f "$ACTIVE_WORK" ]; then
  mkdir -p "$(dirname "$ACTIVE_WORK")"
  printf '| Window | Branch | Worktree Path | Area | Started |\n'        > "$ACTIVE_WORK"
  printf '|--------|--------|---------------|------|---------|\\n'         >> "$ACTIVE_WORK"
  echo "  [OK] Created active-work.md"
fi

# ── plans directory ───────────────────────────────────────────────────────────
mkdir -p "$REPO_ROOT/.claude/plans"

echo ""
echo "Installation complete."
echo ""
echo "Git hooks: pre-commit, pre-push"
HOOK_COUNT=0
if [ -d "$CLAUDE_HOOKS_DIR" ]; then
  HOOK_COUNT=$(find "$CLAUDE_HOOKS_DIR" -maxdepth 1 -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')
fi
echo "Claude guard hooks: $HOOK_COUNT"
echo ""
echo "Next: open Claude Code and run /letsbuild to start a feature."
