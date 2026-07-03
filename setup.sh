#!/usr/bin/env bash
# Claude Code Development Platform — per-fleet-repo guard-hook installer.
#
# Copies the guard-hook scripts from THIS repo's .claude/hooks/ into
# <target-repo>/.claude/hooks/ (mirror: adds new, updates changed, removes
# stray hooks that are no longer in the platform source).
#
# Then prints — but does NOT force — the recommended hooks block to add to
# the target repo's .claude/settings.json.
#
# Usage:
#   bash setup.sh <path-to-fleet-repo>
#
# Examples:
#   bash setup.sh ../fleet-reservations
#   bash setup.sh "/Users/mikekunz/Documents/Volo Technologies/fleet-reservations"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_HOOKS="$SCRIPT_DIR/.claude/hooks"

# ── colour helpers ────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN='' YELLOW='' RED='' BLUE='' BOLD='' NC=''
fi
ok()      { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
added()   { echo -e "  ${GREEN}[ADDED]${NC} $1"; }
changed() { echo -e "  ${YELLOW}[CHANGED]${NC} $1"; }
removed() { echo -e "  ${RED}[REMOVED]${NC} $1"; }

# ── validate args ─────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: bash setup.sh <path-to-fleet-repo>" >&2
  echo "  Example: bash setup.sh ../fleet-reservations" >&2
  exit 1
fi

TARGET="$(cd "$1" && pwd)"

if [ ! -d "$TARGET" ]; then
  echo "ERROR: Target directory not found: $TARGET" >&2
  exit 1
fi

if [ ! -d "$PLATFORM_HOOKS" ]; then
  echo "ERROR: Platform hooks dir not found: $PLATFORM_HOOKS" >&2
  exit 1
fi

REPO_NAME="$(basename "$TARGET")"
say() { echo -e "$@"; }
say ""
say "${BOLD}Installing guard hooks into:${NC} $TARGET"
say ""

# ── mirror .claude/hooks/*.sh into target ─────────────────────────────────────
DEST_HOOKS="$TARGET/.claude/hooks"
mkdir -p "$DEST_HOOKS"

say "${BLUE}=== Guard hooks ===${NC}"

# Add / update hooks from platform
for src_hook in "$PLATFORM_HOOKS"/*.sh; do
  [ -f "$src_hook" ] || continue
  name="$(basename "$src_hook")"
  dest_hook="$DEST_HOOKS/$name"
  if [ ! -f "$dest_hook" ]; then
    cp "$src_hook" "$dest_hook"
    chmod +x "$dest_hook"
    added "$name"
  elif diff -q "$src_hook" "$dest_hook" >/dev/null 2>&1; then
    ok "$name"
  else
    cp "$src_hook" "$dest_hook"
    chmod +x "$dest_hook"
    changed "$name"
  fi
done

# Remove stray hooks in target that are no longer in platform
while IFS= read -r -d '' dest_hook; do
  name="$(basename "$dest_hook")"
  if [ ! -f "$PLATFORM_HOOKS/$name" ]; then
    rm -f "$dest_hook"
    removed "$name  (no longer in platform)"
  fi
done < <(find "$DEST_HOOKS" -maxdepth 1 -type f -name "*.sh" -print0)

say ""
say "${GREEN}${BOLD}Guard hooks installed.${NC}"

# ── print recommended settings.json hooks block ───────────────────────────────
say ""
say "${BOLD}Recommended .claude/settings.json hooks block for ${REPO_NAME}:${NC}"
say "(Copy this into ${TARGET}/.claude/settings.json — do NOT force-overwrite the whole file.)"
say ""

cat << 'EOSETTINGS'
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/block-protected-branch.sh" },
          { "type": "command", "command": "bash .claude/hooks/block-no-verify.sh" },
          { "type": "command", "command": "bash .claude/hooks/block-destructive-git.sh" },
          { "type": "command", "command": "bash .claude/hooks/block-gh-merge.sh" },
          { "type": "command", "command": "bash .claude/hooks/block-rebase-interactive.sh" },
          { "type": "command", "command": "bash .claude/hooks/block-file-redirect.sh" },
          { "type": "command", "command": "bash .claude/hooks/check-work-registration.sh" },
          { "type": "command", "command": "bash .claude/hooks/check-branch-prefix.sh" },
          { "type": "command", "command": "bash .claude/hooks/enforce-worktree.sh" }
        ]
      },
      {
        "matcher": "Edit",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/enforce-worktree.sh" }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/enforce-worktree.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/session-tracker.sh" }
        ]
      }
    ]
  }
EOSETTINGS

say ""
