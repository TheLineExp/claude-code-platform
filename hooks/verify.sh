#!/usr/bin/env bash
# Verify installed git hooks match templates.  Detects drift.
# Run periodically or in CI: bash hooks/verify.sh
#
# Exits 0 if all hooks match; exits 1 if any drift is detected.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || REPO_ROOT="$PWD"
HOOKS_DIR="$REPO_ROOT/hooks"
GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"
CLAUDE_HOOKS_DIR="$REPO_ROOT/.claude/hooks"
DRIFT=0

echo "Verifying hook installation..."
echo ""

# ── git hooks ─────────────────────────────────────────────────────────────────
for hook in pre-commit pre-push; do
  if [ ! -f "$HOOKS_DIR/$hook" ]; then
    echo "  [SKIP] $hook — no template in hooks/"
    continue
  fi

  if [ ! -f "$GIT_HOOKS_DIR/$hook" ]; then
    echo "  [MISSING] $hook — not installed in .git/hooks/"
    DRIFT=1
    continue
  fi

  if diff -q "$HOOKS_DIR/$hook" "$GIT_HOOKS_DIR/$hook" >/dev/null 2>&1; then
    echo "  [OK] $hook — matches template"
  else
    echo "  [DRIFT] $hook — installed version differs from template"
    DRIFT=1
  fi
done

# ── Claude Code guard hooks: executable check ────────────────────────────────
if [ -d "$CLAUDE_HOOKS_DIR" ]; then
  while IFS= read -r -d '' hook_file; do
    name="$(basename "$hook_file")"
    if [ ! -x "$hook_file" ]; then
      echo "  [WARN] $name — not executable (run: chmod +x '$hook_file')"
      DRIFT=1
    fi
  done < <(find "$CLAUDE_HOOKS_DIR" -maxdepth 1 -name "*.sh" -print0 2>/dev/null)
fi

echo ""
if [ "$DRIFT" -eq 0 ]; then
  echo "All hooks match templates."
  exit 0
else
  echo "Drift detected.  Run: bash hooks/install.sh"
  exit 1
fi
