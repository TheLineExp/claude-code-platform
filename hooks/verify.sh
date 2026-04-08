#!/bin/bash
# Verify installed git hooks match templates. Detects drift.
# Run periodically or in CI: bash hooks/verify.sh

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
HOOKS_DIR="$REPO_ROOT/hooks"
GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"
DRIFT=0

echo "Verifying hook installation..."
echo ""

for hook in pre-commit pre-push; do
  if [ ! -f "$HOOKS_DIR/$hook" ]; then
    echo "  [SKIP] $hook — no template found"
    continue
  fi

  if [ ! -f "$GIT_HOOKS_DIR/$hook" ]; then
    echo "  [MISSING] $hook — not installed"
    DRIFT=1
    continue
  fi

  if ! diff -q "$HOOKS_DIR/$hook" "$GIT_HOOKS_DIR/$hook" > /dev/null 2>&1; then
    echo "  [DRIFT] $hook — installed version differs from template"
    DRIFT=1
  else
    echo "  [OK] $hook — matches template"
  fi
done

# Check Claude Code hooks are executable
CLAUDE_HOOKS_DIR="$REPO_ROOT/.claude/hooks"
if [ -d "$CLAUDE_HOOKS_DIR" ]; then
  for hook_file in "$CLAUDE_HOOKS_DIR"/*.sh; do
    if [ -f "$hook_file" ] && [ ! -x "$hook_file" ]; then
      echo "  [WARN] $(basename "$hook_file") — not executable"
      DRIFT=1
    fi
  done
fi

echo ""
if [ "$DRIFT" -eq 0 ]; then
  echo "All hooks match templates."
else
  echo "Drift detected. Run 'bash hooks/install.sh' to re-sync."
  exit 1
fi
