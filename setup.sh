#!/bin/bash
# Claude Code Development Platform — Interactive Setup Wizard
# Run this script to configure the platform for your project.
#
# Usage: bash setup.sh
# Works on: macOS, Linux, Windows (Git Bash / MSYS2)

set -e

# Colors (if terminal supports them)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN='' YELLOW='' RED='' BLUE='' BOLD='' NC=''
fi

echo ""
echo -e "${BOLD}Claude Code Development Platform — Setup Wizard${NC}"
echo "================================================"
echo ""
echo "This wizard configures the platform for your project."
echo "Press Enter to accept defaults shown in [brackets]."
echo ""

# --- Helper functions ---

ask() {
  local prompt="$1" default="$2" var="$3"
  if [ -n "$default" ]; then
    read -rp "$prompt [$default]: " value
    eval "$var=\"${value:-$default}\""
  else
    read -rp "$prompt: " value
    eval "$var=\"$value\""
  fi
}

ask_yn() {
  local prompt="$1" default="$2"
  read -rp "$prompt [$default]: " value
  value="${value:-$default}"
  case "$value" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# --- Phase 1: Project Configuration ---

echo -e "${BLUE}=== Project Configuration ===${NC}"
echo ""

ask "Project name" "my-project" PROJECT_NAME
ask "GitHub org/repo (e.g., myorg/my-project)" "" GITHUB_REPO
ask "Repo directory name" "$PROJECT_NAME" REPO_DIR

echo ""
echo -e "${BLUE}=== Branch Configuration ===${NC}"
echo ""

ask "Production branch" "main" PRODUCTION_BRANCH
ask "Staging branch" "staging" STAGING_BRANCH
ask "Feature branch prefix" "feature/" FEATURE_PREFIX
ask "Owner prefixes (comma-separated, for human commits)" "mk" OWNER_PREFIXES

echo ""
echo -e "${BLUE}=== Agent Configuration ===${NC}"
echo ""

ask "Max concurrent agent windows" "3" MAX_WINDOWS
echo "Merge policy:"
echo "  block-all     — Agents never merge any PRs (recommended)"
echo "  allow-staging — Agents can merge staging PRs, not production"
ask "Merge policy" "block-all" MERGE_POLICY

echo ""
echo -e "${BLUE}=== Testing ===${NC}"
echo ""

ask "Test command" "npm test" TEST_COMMAND
ask "Test runner prefix (e.g., 'docker-compose exec backend', or leave empty)" "" TEST_RUNNER

echo ""
echo -e "${BLUE}=== Deployment (optional — press Enter to skip) ===${NC}"
echo ""

ask "Staging URL" "" STAGING_URL
ask "Production URL" "" PRODUCTION_URL
ask "Health endpoint" "/health" HEALTH_ENDPOINT

echo ""
echo -e "${BLUE}=== Feature Tier ===${NC}"
echo ""
echo "Choose which features to install:"
echo ""
echo "  minimal   — Safety hooks + /letsbuild only"
echo "  standard  — + /shipit, /code-review, /pre-deploy, /plan-eng-review,"
echo "              /retro, /token-audit, code-reviewer agent (recommended)"
echo "  full      — + all review skills, all agents, /effort-optimizer,"
echo "              /document-release, /feature, /perf-test"
echo ""
ask "Feature tier" "standard" TIER

echo ""
echo -e "${BLUE}=== Permission Preset ===${NC}"
echo ""
echo "How much should Claude auto-approve without asking?"
echo ""
echo "  cautious    — Auto-approve reads only; prompt for everything else"
echo "  standard    — Auto-approve reads, edits, common git/npm (recommended)"
echo "  power-user  — Auto-approve almost everything; hooks are the safety net"
echo ""
ask "Permission preset" "standard" PERMISSION_PRESET

# --- Phase 2: Generate platform.config.json ---

echo ""
echo -e "${YELLOW}Generating configuration...${NC}"
echo ""

# Convert comma-separated owner prefixes to JSON array
OWNER_JSON=$(echo "$OWNER_PREFIXES" | sed 's/,/", "/g; s/^/"/; s/$/"/')

# Convert protected branches to JSON array
PROTECTED_JSON="\"$STAGING_BRANCH\", \"$PRODUCTION_BRANCH\""

cat > platform.config.json << EOCFG
{
  "\$schema": "./platform.schema.json",
  "version": "1.0.0",
  "project": {
    "name": "$PROJECT_NAME",
    "repo": "$GITHUB_REPO",
    "repoDir": "$REPO_DIR"
  },
  "branches": {
    "production": "$PRODUCTION_BRANCH",
    "staging": "$STAGING_BRANCH",
    "protected": [$PROTECTED_JSON],
    "featurePrefix": "$FEATURE_PREFIX",
    "ownerPrefixes": [$OWNER_JSON]
  },
  "agents": {
    "maxWindows": $MAX_WINDOWS,
    "mergePolicy": "$MERGE_POLICY"
  },
  "testing": {
    "command": "$TEST_COMMAND",
    "runner": "$TEST_RUNNER",
    "coverageThreshold": 50
  },
  "deployment": {
    "githubOrg": "$(echo "$GITHUB_REPO" | cut -d'/' -f1)",
    "githubRepo": "$(echo "$GITHUB_REPO" | cut -d'/' -f2)",
    "stagingUrl": "$STAGING_URL",
    "productionUrl": "$PRODUCTION_URL",
    "healthEndpoint": "$HEALTH_ENDPOINT"
  },
  "security": {
    "secretPatterns": [".env", ".env.*", "credentials*", "*secret*", "*.pem", "*.key"]
  },
  "permissions": {
    "preset": "$PERMISSION_PRESET"
  }
}
EOCFG

echo -e "  ${GREEN}[OK]${NC} platform.config.json"

# --- Phase 3: Generate CLAUDE.md from template ---

sed \
  -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
  -e "s|{{REPO_DIR}}|$REPO_DIR|g" \
  -e "s|{{PROTECTED_BRANCHES}}|$STAGING_BRANCH, $PRODUCTION_BRANCH|g" \
  -e "s|{{STAGING_BRANCH}}|$STAGING_BRANCH|g" \
  -e "s|{{PRODUCTION_BRANCH}}|$PRODUCTION_BRANCH|g" \
  -e "s|{{FEATURE_PREFIX}}|$FEATURE_PREFIX|g" \
  -e "s|{{STAGING_URL}}|${STAGING_URL:-<staging-url>}|g" \
  -e "s|{{PRODUCTION_URL}}|${PRODUCTION_URL:-<production-url>}|g" \
  -e "s|{{HEALTH_ENDPOINT}}|$HEALTH_ENDPOINT|g" \
  -e "s|{{GITHUB_REPO}}|${GITHUB_REPO:-<org/repo>}|g" \
  CLAUDE.md > CLAUDE.md.tmp && mv CLAUDE.md.tmp CLAUDE.md

echo -e "  ${GREEN}[OK]${NC} CLAUDE.md generated"

# --- Phase 4: Generate settings.json based on permission preset ---

generate_permissions() {
  local preset="$1"
  case "$preset" in
    cautious)
      cat << 'EOPERM'
    "allow": [
      "Read",
      "Glob",
      "Grep"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(git push --force *)",
      "Bash(git push -f *)",
      "Bash(git reset --hard*)",
      "Bash(git checkout .)",
      "Bash(gh pr merge *)"
    ]
EOPERM
      ;;
    standard)
      cat << 'EOPERM'
    "allow": [
      "Read", "Edit", "Write", "Glob", "Grep", "WebFetch", "WebSearch",
      "Bash(npm *)", "Bash(npx *)", "Bash(node *)",
      "Bash(git status*)", "Bash(git log*)", "Bash(git diff*)",
      "Bash(git branch*)", "Bash(git checkout *)", "Bash(git switch *)",
      "Bash(git add *)", "Bash(git commit *)", "Bash(git stash*)",
      "Bash(git worktree *)", "Bash(git rev-parse *)",
      "Bash(git merge-tree *)", "Bash(git merge-base *)",
      "Bash(git remote *)", "Bash(git fetch *)", "Bash(git pull *)",
      "Bash(git show *)", "Bash(git tag *)", "Bash(git rebase *)",
      "Bash(git push origin feature/*)", "Bash(git push -u origin feature/*)",
      "Bash(gh pr create *)", "Bash(gh pr list *)", "Bash(gh pr view *)",
      "Bash(gh pr status*)", "Bash(gh pr checks *)",
      "Bash(gh run *)", "Bash(gh workflow *)", "Bash(gh api *)",
      "Bash(docker-compose *)", "Bash(docker compose *)",
      "Bash(docker exec *)", "Bash(docker logs *)", "Bash(docker ps*)",
      "Bash(ls *)", "Bash(ls)", "Bash(cat *)", "Bash(head *)", "Bash(tail *)",
      "Bash(wc *)", "Bash(mkdir *)", "Bash(cp *)", "Bash(mv *)",
      "Bash(diff *)", "Bash(sort *)", "Bash(which *)", "Bash(curl -s *)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(git push --force *)", "Bash(git push -f *)",
      "Bash(git push --force-with-lease *)",
      "Bash(git push origin ${PRODUCTION_BRANCH}*)",
      "Bash(git push origin ${STAGING_BRANCH}*)",
      "Bash(git reset --hard*)", "Bash(git checkout .)",
      "Bash(git clean *)", "Bash(gh pr merge *)"
    ]
EOPERM
      ;;
    power-user)
      cat << 'EOPERM'
    "allow": [
      "Read", "Edit", "Write", "Glob", "Grep", "WebFetch", "WebSearch",
      "Bash(npm *)", "Bash(npx *)", "Bash(node *)",
      "Bash(git *)", "Bash(gh *)",
      "Bash(docker*)", "Bash(az *)", "Bash(curl *)",
      "Bash(ls *)", "Bash(ls)", "Bash(cat *)", "Bash(head *)", "Bash(tail *)",
      "Bash(wc *)", "Bash(mkdir *)", "Bash(cp *)", "Bash(mv *)",
      "Bash(diff *)", "Bash(sort *)", "Bash(which *)",
      "Bash(pip *)", "Bash(python *)", "Bash(pytest *)",
      "Bash(bundle *)", "Bash(rails *)", "Bash(rake *)",
      "Bash(go *)", "Bash(cargo *)", "Bash(make *)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(git push --force *)", "Bash(git push -f *)",
      "Bash(git push --force-with-lease *)",
      "Bash(git push origin ${PRODUCTION_BRANCH}*)",
      "Bash(git push origin ${STAGING_BRANCH}*)",
      "Bash(git reset --hard*)", "Bash(git checkout .)",
      "Bash(git clean *)", "Bash(gh pr merge *)"
    ]
EOPERM
      ;;
  esac
}

PERMS=$(generate_permissions "$PERMISSION_PRESET")

# The settings.json is already in .claude/ — overwrite with generated version
cat > .claude/settings.json << EOSETTINGS
{
  "permissions": {
$PERMS
  },
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
    ],
    "PostToolUseFailure": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/error-handler.sh" }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "auto",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/compact-notifier.sh" }
        ]
      }
    ]
  }
}
EOSETTINGS

echo -e "  ${GREEN}[OK]${NC} .claude/settings.json (preset: $PERMISSION_PRESET)"

# --- Phase 5: Remove skills/agents not in selected tier ---

remove_if_not_tier() {
  local path="$1" required_tier="$2"
  case "$TIER" in
    minimal)
      if [ "$required_tier" != "minimal" ]; then
        rm -rf "$path" 2>/dev/null
      fi
      ;;
    standard)
      if [ "$required_tier" = "full" ]; then
        rm -rf "$path" 2>/dev/null
      fi
      ;;
    full)
      # Keep everything
      ;;
  esac
}

# Minimal: only letsbuild
remove_if_not_tier ".claude/skills/shipit" "standard"
remove_if_not_tier ".claude/skills/code-review" "standard"
remove_if_not_tier ".claude/skills/pre-deploy" "standard"
remove_if_not_tier ".claude/skills/plan-eng-review" "standard"
remove_if_not_tier ".claude/skills/retro" "standard"
remove_if_not_tier ".claude/skills/token-audit" "standard"
remove_if_not_tier ".claude/agents/code-reviewer.md" "standard"

# Standard: excludes these
remove_if_not_tier ".claude/skills/plan-design-review" "full"
remove_if_not_tier ".claude/skills/plan-ceo-review" "full"
remove_if_not_tier ".claude/skills/document-release" "full"
remove_if_not_tier ".claude/skills/feature" "full"
remove_if_not_tier ".claude/skills/security-review" "full"
remove_if_not_tier ".claude/skills/api-review" "full"
remove_if_not_tier ".claude/skills/perf-test" "full"
remove_if_not_tier ".claude/skills/effort-optimizer" "full"
remove_if_not_tier ".claude/agents/deploy-verifier.md" "full"
remove_if_not_tier ".claude/agents/perf-tester.md" "full"

SKILLS_COUNT=$(find .claude/skills -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
AGENTS_COUNT=$(find .claude/agents -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
echo -e "  ${GREEN}[OK]${NC} $SKILLS_COUNT skills, $AGENTS_COUNT agents (tier: $TIER)"

# --- Phase 6: Install git hooks ---

echo ""
echo -e "${YELLOW}Installing hooks...${NC}"
echo ""

bash hooks/install.sh 2>/dev/null || {
  echo -e "  ${YELLOW}[WARN]${NC} Git hooks not installed (not a git repo yet?)"
  echo "  Run 'bash hooks/install.sh' after 'git init'"
}

# --- Phase 7: Create .gitignore entries ---

if ! grep -q "settings.local.json" .gitignore 2>/dev/null; then
  cat >> .gitignore << 'EOGI'

# Claude Code Platform
.claude/settings.local.json
.claude/plans/
.context/
/tmp/
EOGI
  echo -e "  ${GREEN}[OK]${NC} .gitignore updated"
fi

# --- Phase 8: Validation ---

echo ""
echo -e "${YELLOW}Validating installation...${NC}"
echo ""

PASS=0
FAIL=0

check() {
  if [ -f "$1" ] || [ -d "$1" ]; then
    echo -e "  ${GREEN}[OK]${NC} $2"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}[MISSING]${NC} $2"
    FAIL=$((FAIL + 1))
  fi
}

check "platform.config.json" "platform.config.json"
check "CLAUDE.md" "CLAUDE.md"
check ".claude/settings.json" ".claude/settings.json"
check ".claude/hooks/block-protected-branch.sh" "Claude hooks"
check ".claude/hooks/session-tracker.sh" "Session tracker"
check ".claude/hooks/error-handler.sh" "Error handler"
check ".claude/skills/letsbuild/SKILL.md" "letsbuild skill"
check ".claude/window-id" "Window ID sentinel"
check ".claude/active-work.md" "Active work registry"
check "hooks/pre-commit" "Git pre-commit hook"
check "hooks/pre-push" "Git pre-push hook"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}Setup complete! All $PASS checks passed.${NC}"
else
  echo -e "${YELLOW}Setup complete with warnings. $PASS passed, $FAIL missing.${NC}"
fi

echo ""
echo -e "${BOLD}Next steps:${NC}"
echo ""
echo "  1. Review CLAUDE.md and add your project-specific rules"
echo "  2. Create addon files for project-specific checks:"
echo "     - .claude/code-review-addons.md"
echo "     - .claude/security-review-addons.md"
echo "  3. Copy .claude/settings.local.json.example to .claude/settings.local.json"
echo "     and add your personal permission overrides"
echo "  4. Open Claude Code and run /letsbuild to start your first feature"
echo ""
echo "  Documentation: docs/SETUP.md, docs/CUSTOMIZATION.md"
echo ""
