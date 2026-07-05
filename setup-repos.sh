#!/usr/bin/env bash
# Claude Code Development Platform — multi-repo scaffolder.
#
# Reads repos.json; for each repo: clones if absent, installs git hooks,
# scaffolds .env files from their *.example siblings, and registers the
# graphify per-repo post-commit hook (if graphify is installed).
#
# Usage:
#   bash setup-repos.sh              # use repos.json reposRoot or parent of this repo
#   REPOS_ROOT="/path/to/repos" bash setup-repos.sh
#   DRY_RUN=1 bash setup-repos.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/repos.json"

# ── colour helpers ────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
run()  {
  if [ -n "${DRY_RUN:-}" ]; then echo "  (dry-run) $*"; else eval "$@"; fi
}

# ── prerequisites ─────────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { echo "jq is required — brew install jq" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "repos.json not found at $MANIFEST" >&2; exit 1; }

# ── resolve repos root ────────────────────────────────────────────────────────
# Priority: manifest.reposRoot > $REPOS_ROOT env var > parent of this repo
ROOT="$(jq -r '.reposRoot // ""' "$MANIFEST")"
[ -z "$ROOT" ] && ROOT="${REPOS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# Normalise: no trailing slash
ROOT="${ROOT%/}"

echo -e "${BOLD}Scaffolding repos under:${NC} $ROOT"
echo ""

# ── iterate repos ─────────────────────────────────────────────────────────────
COUNT="$(jq '.repos | length' "$MANIFEST")"
for i in $(seq 0 $((COUNT - 1))); do
  name="$(jq -r ".repos[$i].name" "$MANIFEST")"
  remote="$(jq -r ".repos[$i].remote" "$MANIFEST")"
  dir="$(jq -r ".repos[$i].dir" "$MANIFEST")"
  target="$ROOT/$dir"
  echo -e "${BLUE}=== $name ($remote) ===${NC}"

  # 1. Clone if absent
  if [ -d "$target/.git" ]; then
    ok "already cloned: $target"
  else
    run "git clone 'https://github.com/$remote.git' '$target'"
    ok "cloned -> $target"
  fi

  # 2. Install the repo's OWN git hooks if it ships them (pre-commit etc.). The
  # platform GUARD hooks are GLOBAL now — deployed once to ~/.claude via
  # setup-machine.sh and fired for every session — so there is nothing per-repo
  # to install here.
  if [ -f "$target/hooks/install.sh" ]; then
    run "bash '$target/hooks/install.sh'"
    ok "git hooks installed"
  else
    ok "no repo git hooks in $name (guard hooks are global — run setup-machine.sh)"
  fi

  # 3. Scaffold .env files from their *.example siblings (never overwrite)
  while IFS= read -r envf; do
    [ -n "$envf" ] || continue
    if [ -f "$target/$envf" ]; then
      ok ".env present: $envf"
    elif [ -f "$target/$envf.example" ]; then
      run "cp '$target/$envf.example' '$target/$envf'"
      warn "scaffolded $envf from example — FILL IN SECRETS"
    else
      warn "no $envf or $envf.example in $name — skip"
    fi
  done < <(jq -r ".repos[$i].envFiles[]? // empty" "$MANIFEST")

  # 4. Register graphify per-repo post-commit hook (free, AST-only)
  if command -v graphify >/dev/null 2>&1 && [ -d "$target/.git" ]; then
    run "(cd '$target' && graphify install-hook 2>/dev/null) || true"
    ok "graphify post-commit hook registered"
  fi

  echo ""
done

echo -e "${GREEN}${BOLD}Repo scaffolding complete.${NC}"
echo "Optional cross-repo GLOBAL graph (costs API tokens) — see docs/NEW_PC.md § Graphify."
