#!/bin/bash
# Claude Code Development Platform — multi-repo scaffolder.
#
# Iterates repos.json: for each repo, clone (if absent), install git hooks, scaffold
# .env files from their examples, and register the graphify per-repo post-commit hook.
# This is the "link to my repos" step. To target a different repo set, edit repos.json.
#
# Usage:
#   bash setup-repos.sh                 # interactive root
#   REPOS_ROOT=/c/Users/you/Documents bash setup-repos.sh
#   DRY_RUN=1 bash setup-repos.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/repos.json"

if [ -t 1 ]; then GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else GREEN='' YELLOW='' BLUE='' BOLD='' NC=''; fi
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
run()  { if [ -n "$DRY_RUN" ]; then echo "  (dry-run) $*"; else eval "$@"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required to read repos.json — install jq and re-run."; exit 1; }
[ -f "$MANIFEST" ] || { echo "repos.json not found at $MANIFEST"; exit 1; }

# Resolve root: manifest.reposRoot > $REPOS_ROOT > parent of platform repo.
ROOT="$(jq -r '.reposRoot // ""' "$MANIFEST")"
[ -z "$ROOT" ] && ROOT="${REPOS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ROOT="$(echo "$ROOT" | sed 's#\\#/#g')"
echo -e "${BOLD}Scaffolding repos under:${NC} $ROOT"
echo ""

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
    run "git clone \"https://github.com/$remote.git\" \"$target\""
    ok "cloned -> $target"
  fi

  # 2. Install git hooks (idempotent; the repo ships its own hooks/install.sh)
  if [ -f "$target/hooks/install.sh" ]; then
    run "(cd \"$target\" && bash hooks/install.sh)"
    ok "git hooks installed"
  else
    warn "no hooks/install.sh in $name — run 'bash setup.sh' inside it to scaffold the platform first"
  fi

  # 3. Scaffold .env files from their *.example siblings (never overwrite)
  for envf in $(jq -r ".repos[$i].envFiles[]? // empty" "$MANIFEST"); do
    if [ -f "$target/$envf" ]; then
      ok ".env present: $envf"
    elif [ -f "$target/$envf.example" ]; then
      run "cp \"$target/$envf.example\" \"$target/$envf\""
      warn "scaffolded $envf from example — FILL IN SECRETS (see docs/NEW_PC.md § Secrets)"
    else
      warn "no $envf or $envf.example in $name — skip"
    fi
  done

  # 4. Register graphify per-repo post-commit hook (free, AST-only) if graphify is installed
  if command -v graphify >/dev/null 2>&1 && [ -d "$target/.git" ]; then
    run "(cd \"$target\" && graphify install-hook 2>/dev/null) || true"
    ok "graphify post-commit hook registered (if supported)"
  fi
  echo ""
done

echo -e "${GREEN}${BOLD}Repo scaffolding complete.${NC}"
echo "Optional cross-repo GLOBAL graph (costs API tokens) — see docs/NEW_PC.md § Graphify."
