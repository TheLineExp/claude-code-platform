#!/usr/bin/env bash
# Claude Code Development Platform — MACHINE bootstrap (user-global layer).
#
# Syncs the managed set of user-global Claude Code files from platform/global/
# into ~/.claude.  Single Mac machine; no template substitution needed.
# For a future new machine: pass --home /path/to/new/home to override HOME,
# or do a one-time  sed -i 's|/Users/mikekunz|/Users/newuser|g' on the
# canonical templates after adapting them.
#
# Usage:
#   bash setup-machine.sh          # sync mode: backup, apply, summarise
#   bash setup-machine.sh --diff   # diff mode: no writes; exit 1 on drift
#   bash setup-machine.sh --help
#   bash setup-machine.sh --home /Users/newuser   # override home dir

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_SRC="$SCRIPT_DIR/platform/global"

# ── colour helpers ────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN='' YELLOW='' RED='' BLUE='' BOLD='' NC=''
fi
say()    { echo -e "$@"; }
ok()     { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
added()  { echo -e "  ${GREEN}[ADDED]${NC} $1"; }
changed(){ echo -e "  ${YELLOW}[CHANGED]${NC} $1"; }
removed(){ echo -e "  ${RED}[REMOVED]${NC} $1"; }
missing(){ echo -e "  ${RED}[MISSING]${NC} $1"; }
stray()  { echo -e "  ${RED}[STRAY]${NC} $1"; }

# ── arg parsing ───────────────────────────────────────────────────────────────
DIFF_MODE=0
OVERRIDE_HOME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --diff)   DIFF_MODE=1 ; shift ;;
    --home)   OVERRIDE_HOME="$2"; shift 2 ;;
    --help|-h)
      say "Usage: bash setup-machine.sh [--diff] [--home <dir>]"
      say ""
      say "  (no flags)      Sync mode: back up managed live files, then apply canonical."
      say "  --diff          Diff mode: print IDENTICAL/DIFFERS/MISSING/STRAY; exit 1 on drift."
      say "  --home <dir>    Override HOME (default: \$HOME = $HOME)."
      say ""
      say "Managed set:"
      say "  platform/global/skills/         -> ~/.claude/skills/        (mirror)"
      say "  platform/global/agents/         -> ~/.claude/agents/        (mirror)"
      say "  platform/global/claude-CLAUDE.template.md  -> ~/.claude/CLAUDE.md"
      say "  platform/global/claude-settings.template.json -> ~/.claude/settings.json"
      say "  platform/global/backlog-gate.js -> ~/.claude/hooks/backlog-gate.js"
      say "  platform/global/statusline-command.sh -> ~/.claude/statusline-command.sh"
      say ""
      say "  Retired: ~/.claude/hooks/graphify-autoquery.js is REMOVED if present."
      exit 0 ;;
    *) echo "Unknown option: $1  (use --help)" >&2; exit 1 ;;
  esac
done

CLAUDE_HOME="${OVERRIDE_HOME:-$HOME}/.claude"

# ── sanity checks ─────────────────────────────────────────────────────────────
[ -d "$GLOBAL_SRC" ] || { echo "ERROR: $GLOBAL_SRC not found." >&2; exit 1; }

# ── backup helpers (sync mode only) ──────────────────────────────────────────
BACKUP_DIR=""
ensure_backup_dir() {
  if [ -z "$BACKUP_DIR" ]; then
    BACKUP_DIR="$CLAUDE_HOME/backups/$(date '+%Y-%m-%d-%H%M%S')"
    mkdir -p "$BACKUP_DIR"
  fi
}

backup_path() {
  # backup_path <live-path> <label-for-backup-subdir>
  local src="$1" label="$2"
  [ -e "$src" ] || return 0
  ensure_backup_dir
  local dest="$BACKUP_DIR/$label"
  mkdir -p "$(dirname "$dest")"
  cp -r "$src" "$dest"
}

# ── diff mode helpers ─────────────────────────────────────────────────────────
DRIFT=0
diff_file() {
  local src="$1" live="$2" label="$3"
  if [ ! -e "$live" ]; then
    missing "MISSING  $label"
    DRIFT=1
  elif diff -q "$src" "$live" >/dev/null 2>&1; then
    ok "IDENTICAL $label"
  else
    say "  ${YELLOW}[DIFFERS]${NC} $label"
    { diff -u "$live" "$src" || true; } | head -n 22 | sed 's/^/    /' || true
    DRIFT=1
  fi
}

# ── MANAGED FILE LIST ─────────────────────────────────────────────────────────
#
# Single files (src -> live)
declare -a SRC_FILES=( \
  "$GLOBAL_SRC/claude-CLAUDE.template.md" \
  "$GLOBAL_SRC/claude-settings.template.json" \
  "$GLOBAL_SRC/backlog-gate.js" \
  "$GLOBAL_SRC/statusline-command.sh" \
)
declare -a LIVE_FILES=( \
  "$CLAUDE_HOME/CLAUDE.md" \
  "$CLAUDE_HOME/settings.json" \
  "$CLAUDE_HOME/hooks/backlog-gate.js" \
  "$CLAUDE_HOME/statusline-command.sh" \
)

# ── DIFF MODE ─────────────────────────────────────────────────────────────────
if [ "$DIFF_MODE" -eq 1 ]; then
  say "${BOLD}Diff mode — no writes${NC}  (canonical: $GLOBAL_SRC)"
  say ""

  # Single files
  for i in "${!SRC_FILES[@]}"; do
    src="${SRC_FILES[$i]}"
    live="${LIVE_FILES[$i]}"
    label="${live#"$CLAUDE_HOME/"}"
    diff_file "$src" "$live" "$label"
  done

  # Retired file that must NOT exist
  RETIRED="$CLAUDE_HOME/hooks/graphify-autoquery.js"
  if [ -e "$RETIRED" ]; then
    stray "STRAY    hooks/graphify-autoquery.js  (retired — should be removed)"
    DRIFT=1
  fi

  say ""

  # Skills mirror
  say "  ${BLUE}Skills:${NC}"
  for canonical_skill in "$GLOBAL_SRC/skills"/*/; do
    [ -d "$canonical_skill" ] || continue
    name="$(basename "$canonical_skill")"
    live_skill="$CLAUDE_HOME/skills/$name"
    if [ ! -d "$live_skill" ]; then
      missing "MISSING  skills/$name"
      DRIFT=1
    else
      # Compare each file in the skill dir
      while IFS= read -r -d '' rel_src; do
        rel="${rel_src#"$canonical_skill"}"
        live_f="$live_skill/$rel"
        if [ ! -f "$live_f" ]; then
          missing "MISSING  skills/$name/$rel"
          DRIFT=1
        elif ! diff -q "$rel_src" "$live_f" >/dev/null 2>&1; then
          say "  ${YELLOW}[DIFFERS]${NC} skills/$name/$rel"
          { diff -u "$live_f" "$rel_src" || true; } | head -n 22 | sed 's/^/    /' || true
          DRIFT=1
        else
          ok "IDENTICAL skills/$name/$rel"
        fi
      done < <(find "$canonical_skill" -type f -print0)
    fi
  done

  # Stray skills (in live but not in canonical)
  if [ -d "$CLAUDE_HOME/skills" ]; then
    while IFS= read -r -d '' live_skill; do
      name="$(basename "$live_skill")"
      if [ ! -d "$GLOBAL_SRC/skills/$name" ]; then
        stray "STRAY    skills/$name"
        DRIFT=1
      fi
    done < <(find "$CLAUDE_HOME/skills" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  say ""

  # Agents mirror
  say "  ${BLUE}Agents:${NC}"
  for canonical_agent in "$GLOBAL_SRC/agents"/*.md; do
    [ -f "$canonical_agent" ] || continue
    name="$(basename "$canonical_agent")"
    live_agent="$CLAUDE_HOME/agents/$name"
    diff_file "$canonical_agent" "$live_agent" "agents/$name"
  done

  # Stray agents
  if [ -d "$CLAUDE_HOME/agents" ]; then
    while IFS= read -r -d '' live_agent; do
      name="$(basename "$live_agent")"
      if [ ! -f "$GLOBAL_SRC/agents/$name" ]; then
        stray "STRAY    agents/$name"
        DRIFT=1
      fi
    done < <(find "$CLAUDE_HOME/agents" -maxdepth 1 -type f -name "*.md" -print0)
  fi

  # Guard hooks mirror (*.sh)
  say "  ${BLUE}Guard hooks:${NC}"
  for canonical_hook in "$GLOBAL_SRC/hooks"/*.sh; do
    [ -f "$canonical_hook" ] || continue
    name="$(basename "$canonical_hook")"
    diff_file "$canonical_hook" "$CLAUDE_HOME/hooks/$name" "hooks/$name"
  done
  if [ -d "$CLAUDE_HOME/hooks" ]; then
    while IFS= read -r -d '' live_hook; do
      name="$(basename "$live_hook")"
      if [ ! -f "$GLOBAL_SRC/hooks/$name" ]; then
        stray "STRAY    hooks/$name"
        DRIFT=1
      fi
    done < <(find "$CLAUDE_HOME/hooks" -maxdepth 1 -type f -name "*.sh" -print0)
  fi

  say ""
  if [ "$DRIFT" -eq 0 ]; then
    say "${GREEN}${BOLD}No drift — live matches canonical.${NC}"
    exit 0
  else
    say "${RED}${BOLD}Drift detected.${NC}  Run: bash setup-machine.sh"
    exit 1
  fi
fi

# ── SYNC MODE ─────────────────────────────────────────────────────────────────
say ""
say "${BOLD}Machine sync${NC}  canonical=$GLOBAL_SRC  live=$CLAUDE_HOME"
say ""

# Ensure directory structure
mkdir -p "$CLAUDE_HOME/hooks" "$CLAUDE_HOME/skills" "$CLAUDE_HOME/agents" "$CLAUDE_HOME/backups"

# Track changes for summary
CHANGED_COUNT=0
ADDED_COUNT=0
REMOVED_COUNT=0

sync_file() {
  local src="$1" live="$2" label="$3"
  mkdir -p "$(dirname "$live")"
  if [ ! -e "$live" ]; then
    cp "$src" "$live"
    added "$label"
    ADDED_COUNT=$((ADDED_COUNT + 1))
  elif diff -q "$src" "$live" >/dev/null 2>&1; then
    ok "$label"
  else
    backup_path "$live" "$label"
    cp "$src" "$live"
    changed "$label"
    CHANGED_COUNT=$((CHANGED_COUNT + 1))
  fi
}

# Single files
say "${BLUE}=== Single files ===${NC}"
for i in "${!SRC_FILES[@]}"; do
  src="${SRC_FILES[$i]}"
  live="${LIVE_FILES[$i]}"
  label="${live#"$CLAUDE_HOME/"}"
  sync_file "$src" "$live" "$label"
done

# Make statusline executable
chmod +x "$CLAUDE_HOME/statusline-command.sh"

# Remove retired file
RETIRED="$CLAUDE_HOME/hooks/graphify-autoquery.js"
if [ -e "$RETIRED" ]; then
  backup_path "$RETIRED" "hooks/graphify-autoquery.js"
  rm -f "$RETIRED"
  removed "hooks/graphify-autoquery.js  (retired)"
  REMOVED_COUNT=$((REMOVED_COUNT + 1))
fi

say ""
say "${BLUE}=== Skills (mirror) ===${NC}"

# Copy canonical skills
for canonical_skill in "$GLOBAL_SRC/skills"/*/; do
  [ -d "$canonical_skill" ] || continue
  name="$(basename "$canonical_skill")"
  live_skill="$CLAUDE_HOME/skills/$name"
  if [ ! -d "$live_skill" ]; then
    cp -r "$canonical_skill" "$live_skill"
    added "skills/$name"
    ADDED_COUNT=$((ADDED_COUNT + 1))
  else
    # File-level sync
    while IFS= read -r -d '' rel_src; do
      rel="${rel_src#"$canonical_skill"}"
      live_f="$live_skill/$rel"
      mkdir -p "$(dirname "$live_f")"
      if [ ! -f "$live_f" ]; then
        cp "$rel_src" "$live_f"
        added "skills/$name/$rel"
        ADDED_COUNT=$((ADDED_COUNT + 1))
      elif ! diff -q "$rel_src" "$live_f" >/dev/null 2>&1; then
        backup_path "$live_f" "skills/$name/$rel"
        cp "$rel_src" "$live_f"
        changed "skills/$name/$rel"
        CHANGED_COUNT=$((CHANGED_COUNT + 1))
      else
        ok "skills/$name"
      fi
    done < <(find "$canonical_skill" -type f -print0)

    # Remove live files not in canonical
    while IFS= read -r -d '' live_f; do
      rel="${live_f#"$live_skill/"}"
      if [ ! -f "$canonical_skill/$rel" ]; then
        backup_path "$live_f" "skills/$name/$rel"
        rm -f "$live_f"
        removed "skills/$name/$rel  (not in canonical)"
        REMOVED_COUNT=$((REMOVED_COUNT + 1))
      fi
    done < <(find "$live_skill" -type f -print0)
  fi
done

# Remove stray skill dirs (in live but not in canonical)
if [ -d "$CLAUDE_HOME/skills" ]; then
  while IFS= read -r -d '' live_skill; do
    name="$(basename "$live_skill")"
    if [ ! -d "$GLOBAL_SRC/skills/$name" ]; then
      backup_path "$live_skill" "skills/$name"
      rm -rf "$live_skill"
      removed "skills/$name  (stray — not in canonical)"
      REMOVED_COUNT=$((REMOVED_COUNT + 1))
    fi
  done < <(find "$CLAUDE_HOME/skills" -mindepth 1 -maxdepth 1 -type d -print0)
fi

say ""
say "${BLUE}=== Agents (mirror) ===${NC}"

# Copy canonical agents
for canonical_agent in "$GLOBAL_SRC/agents"/*.md; do
  [ -f "$canonical_agent" ] || continue
  name="$(basename "$canonical_agent")"
  live_agent="$CLAUDE_HOME/agents/$name"
  sync_file "$canonical_agent" "$live_agent" "agents/$name"
done

# Remove stray agent files
if [ -d "$CLAUDE_HOME/agents" ]; then
  while IFS= read -r -d '' live_agent; do
    name="$(basename "$live_agent")"
    if [ ! -f "$GLOBAL_SRC/agents/$name" ]; then
      backup_path "$live_agent" "agents/$name"
      rm -f "$live_agent"
      removed "agents/$name  (stray — not in canonical)"
      REMOVED_COUNT=$((REMOVED_COUNT + 1))
    fi
  done < <(find "$CLAUDE_HOME/agents" -maxdepth 1 -type f -name "*.md" -print0)
fi

say ""
say "${BLUE}=== Guard hooks (mirror: *.sh) ===${NC}"

# Mirror the git-safety guard hooks GLOBALLY. They now fire for every session via
# ~/.claude/settings.json instead of being copied into each repo (kills per-repo drift).
# Scoped to *.sh so backlog-gate.js (synced separately) is untouched.
for canonical_hook in "$GLOBAL_SRC/hooks"/*.sh; do
  [ -f "$canonical_hook" ] || continue
  name="$(basename "$canonical_hook")"
  live_hook="$CLAUDE_HOME/hooks/$name"
  sync_file "$canonical_hook" "$live_hook" "hooks/$name"
  chmod +x "$live_hook" 2>/dev/null || true
done

# Remove stray *.sh hooks (in live but not in canonical)
if [ -d "$CLAUDE_HOME/hooks" ]; then
  while IFS= read -r -d '' live_hook; do
    name="$(basename "$live_hook")"
    if [ ! -f "$GLOBAL_SRC/hooks/$name" ]; then
      backup_path "$live_hook" "hooks/$name"
      rm -f "$live_hook"
      removed "hooks/$name  (stray — not in canonical)"
      REMOVED_COUNT=$((REMOVED_COUNT + 1))
    fi
  done < <(find "$CLAUDE_HOME/hooks" -maxdepth 1 -type f -name "*.sh" -print0)
fi

say ""
say "${BOLD}Summary:${NC}  added=$ADDED_COUNT  changed=$CHANGED_COUNT  removed=$REMOVED_COUNT"
if [ -n "$BACKUP_DIR" ]; then
  say "  Backups in: $BACKUP_DIR"
fi
say ""
say "${GREEN}${BOLD}Sync complete.${NC}  Restart Claude Code to pick up changes."
say ""
