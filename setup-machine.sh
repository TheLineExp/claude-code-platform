#!/bin/bash
# Claude Code Development Platform — MACHINE bootstrap (user-global layer).
#
# This is the NEW-PC step that the per-repo setup.sh wizard does NOT do: it installs
# the user-global Claude + Codex + Graphify config into ~/.claude, ~/.codex, ~/.graphify
# from the sanitized templates in platform/global/, de-hardcoding all machine paths.
#
# Usage:
#   bash setup-machine.sh                  # interactive
#   REPOS_ROOT=/c/Users/you/Documents bash setup-machine.sh   # non-interactive root
#   DRY_RUN=1 bash setup-machine.sh        # print actions, write nothing
#
# Idempotent: backs up any existing target to <file>.bak-<n> before overwriting.
# Works on macOS, Linux, Windows (Git Bash / MSYS2).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_SRC="$SCRIPT_DIR/platform/global"

if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN='' YELLOW='' RED='' BLUE='' BOLD='' NC=''
fi

say()  { echo -e "$@"; }
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
do_or_echo() { if [ -n "$DRY_RUN" ]; then echo "  (dry-run) $*"; else eval "$@"; fi; }

# --- Resolve HOME + REPOS_ROOT in forward-slash form ---
HOME_FS="$(echo "${HOME:-$USERPROFILE}" | sed 's#\\#/#g')"
if [ -z "$REPOS_ROOT" ]; then
  # Default: the parent directory of this platform repo.
  DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  read -rp "Repos root (where your repos live) [$DEFAULT_ROOT]: " REPOS_ROOT
  REPOS_ROOT="${REPOS_ROOT:-$DEFAULT_ROOT}"
fi
REPOS_ROOT_FS="$(echo "$REPOS_ROOT" | sed 's#\\#/#g')"
# MSYS double-slash drive form for Read() globs:  C:/Users/...  ->  /c/Users/...
REPOS_ROOT_UNIX="$(echo "$REPOS_ROOT_FS" | sed -E 's#^([A-Za-z]):#/\L\1#')"
REPOS_ROOT_UNIX="${REPOS_ROOT_UNIX#/}"   # strip a leading slash; template adds //

say ""
say "${BOLD}Machine bootstrap${NC}  HOME=$HOME_FS  REPOS_ROOT=$REPOS_ROOT_FS"
say ""

# --- Helper: backup-then-write (handles files AND directories) ---
backup() {
  local f="$1"
  [ -e "$f" ] || return 0
  local n=1; while [ -e "$f.bak-$n" ]; do n=$((n+1)); done
  do_or_echo "cp -r '$f' '$f.bak-$n'"
  warn "backed up existing $(basename "$f") -> $(basename "$f").bak-$n"
}

subst() {
  # subst <src-template> <dest>  — replaces {{HOME}} {{REPOS_ROOT}} {{REPOS_ROOT_UNIX}}
  sed \
    -e "s#{{HOME}}#$HOME_FS#g" \
    -e "s#{{REPOS_ROOT_UNIX}}#$REPOS_ROOT_UNIX#g" \
    -e "s#{{REPOS_ROOT}}#$REPOS_ROOT_FS#g" \
    "$1"
}

# --- Phase 1: ~/.claude global config ---
say "${BLUE}=== ~/.claude (Claude Code user-global) ===${NC}"
do_or_echo "mkdir -p '$HOME_FS/.claude/hooks' '$HOME_FS/.claude/skills' '$HOME_FS/.claude/plans'"

# settings.json (strip the _comment line; substitute paths)
backup "$HOME_FS/.claude/settings.json"
if [ -z "$DRY_RUN" ]; then
  subst "$GLOBAL_SRC/claude-settings.template.json" \
    | grep -v '"_comment"' > "$HOME_FS/.claude/settings.json"
fi
ok "~/.claude/settings.json (paths de-hardcoded)"

# CLAUDE.md (graphify protocol)
backup "$HOME_FS/.claude/CLAUDE.md"
if [ -z "$DRY_RUN" ]; then subst "$GLOBAL_SRC/claude-CLAUDE.template.md" > "$HOME_FS/.claude/CLAUDE.md"; fi
ok "~/.claude/CLAUDE.md"

# graphify-autoquery hook (verbatim — resolves paths at runtime) + statusline
do_or_echo "cp '$GLOBAL_SRC/graphify-autoquery.js' '$HOME_FS/.claude/hooks/graphify-autoquery.js'"
ok "~/.claude/hooks/graphify-autoquery.js"
do_or_echo "cp '$GLOBAL_SRC/statusline-command.sh' '$HOME_FS/.claude/statusline-command.sh'"
do_or_echo "chmod +x '$HOME_FS/.claude/statusline-command.sh'"
ok "~/.claude/statusline-command.sh"

# user-global skills: the 7 vendored here (graphify, gstack-review, gstack-ship,
# route, todo, feature, shipit) + pm from the platform's own .claude/skills.
# Back up any existing same-named skill dir before replacing it, so a rerun /
# migration never silently discards local customizations.
for s in "$GLOBAL_SRC"/skills/*/; do
  [ -d "$s" ] || continue
  name="$(basename "$s")"
  backup "$HOME_FS/.claude/skills/$name"
  do_or_echo "rm -rf '$HOME_FS/.claude/skills/$name' && cp -r '$s' '$HOME_FS/.claude/skills/$name'"
  ok "skill: $name"
done
if [ -d "$SCRIPT_DIR/.claude/skills/pm" ]; then
  backup "$HOME_FS/.claude/skills/pm"
  do_or_echo "rm -rf '$HOME_FS/.claude/skills/pm' && cp -r '$SCRIPT_DIR/.claude/skills/pm' '$HOME_FS/.claude/skills/pm'"
  ok "skill: pm (from platform .claude/skills)"
fi

# unified cross-repo backlog pointer: /todo + /feature read this file to locate
# the git-synced backlog dir (backlog/FEATURES.md + backlog/TODO.md) inside THIS
# platform repo clone. Written per-machine so the path resolves anywhere.
do_or_echo "mkdir -p '$SCRIPT_DIR/backlog'"
if [ -z "$DRY_RUN" ]; then printf '%s\n' "$SCRIPT_DIR/backlog" > "$HOME_FS/.claude/backlog-location"; fi
ok "~/.claude/backlog-location -> $SCRIPT_DIR/backlog"

# --- Phase 2: ~/.codex portable keys ---
say ""
say "${BLUE}=== ~/.codex (Codex CLI user-global) ===${NC}"
if command -v codex >/dev/null 2>&1; then
  do_or_echo "mkdir -p '$HOME_FS/.codex'"
  if [ ! -f "$HOME_FS/.codex/config.toml" ]; then
    do_or_echo "cp '$GLOBAL_SRC/codex-config.template.toml' '$HOME_FS/.codex/config.toml'"
    ok "~/.codex/config.toml (from template — run 'codex login' to add auth)"
  else
    warn "~/.codex/config.toml exists — NOT overwritten. Merge the keys from platform/global/codex-config.template.toml manually (model, sandbox, features)."
  fi
else
  warn "codex CLI not found on PATH — skipping. Install Codex, then re-run, or copy platform/global/codex-config.template.toml to ~/.codex/config.toml."
fi

# --- Phase 3: Graphify ---
say ""
say "${BLUE}=== Graphify ===${NC}"
if command -v graphify >/dev/null 2>&1; then
  ok "graphify on PATH"
  if [ -f "$HOME_FS/.graphify/global-graph.json" ]; then
    ok "global graph present ($HOME_FS/.graphify/global-graph.json)"
  else
    warn "no global graph yet. Build it (costs API tokens, needs ANTHROPIC_API_KEY):"
    say "       see docs/NEW_PC.md § Graphify for the per-repo extract commands."
  fi
else
  warn "graphify not on PATH. Install per docs/NEW_PC.md, then the autoquery hook activates automatically."
fi

say ""
say "${GREEN}${BOLD}Machine bootstrap complete.${NC}"
say ""
say "${BOLD}Next:${NC}"
say "  1. Run the re-auth checklist (docs/NEW_PC.md § Secrets): claude login, codex login, gh auth login, az login."
say "  2. Run 'bash setup.sh' to scaffold each repo from repos.json."
say "  3. Restart Claude Code so it picks up ~/.claude/settings.json."
say ""
