---
name: shipit
description: Commits changes, pushes to staging, and creates a PR for production deployment. Use when ready to deploy changes or when the user says "ship it", "deploy", or "/shipit".
---

# Ship It Skill

Automates the deployment workflow: commit changes, push feature branch, create staging PR, and optionally create production PR.

## When to Use

- When the user is ready to deploy their changes
- When the user says "ship it", "deploy", or invokes `/shipit`
- After completing a feature or fix that's ready for staging

## Configuration

Read `platform.config.json` for project settings:
- `project.repo` — GitHub org/repo (e.g., "myorg/my-project")
- `branches.production` — production branch name (e.g., "main" or "master")
- `branches.staging` — staging branch name
- `deployment.stagingUrl` — staging URL for post-deploy verification
- `deployment.productionUrl` — production URL
- `deployment.healthEndpoint` — health check path

## Deployment Workflow

### Step 0: Multi-Agent Pre-Flight (MANDATORY)

#### Step 0a: Verify Worktree Isolation

```bash
git rev-parse --git-dir
# Should contain "/worktrees/" (worktree) — NOT ".git" (main repo)
```

If in the main repo, **STOP**: "You should be working in a worktree. Run /letsbuild first."

#### Step 0b: Conflict Pre-Check + Rebase

```bash
STAGING=$(grep -o '"staging"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json 2>/dev/null | head -1 | sed 's/.*"staging"[[:space:]]*:[[:space:]]*"//;s/"$//')
: "${STAGING:=staging}"

git fetch origin "$STAGING"

# Dry-run: detect conflicts without modifying the working tree
MERGE_BASE=$(git merge-base HEAD "origin/$STAGING")
MERGE_RESULT=$(git merge-tree "$MERGE_BASE" HEAD "origin/$STAGING" 2>&1)

if echo "$MERGE_RESULT" | grep -q "<<<<<<"; then
  echo "CONFLICTS DETECTED — resolve before shipping."
  # Do NOT auto-resolve code conflicts
else
  git rebase "origin/$STAGING"
fi
```

#### Step 0c: Check for Conflicting Open PRs

```bash
REPO=$(grep -o '"repo"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json | head -1 | sed 's/.*"repo"[[:space:]]*:[[:space:]]*"//;s/"$//')
gh pr list --repo "$REPO" --base "$STAGING" --state open --json number,headRefName,title --limit 10
```

Warn if another agent has an open PR to staging.

### Step 1: Check Current State

```bash
git status
git branch --show-current
```

Verify you are on a feature branch. If on a protected branch → STOP.

### Step 2: Run Code Review (optional)

If `.claude/code-review-addons.md` exists, run `/code-review` first.

### Step 3: Document Changes

Create a per-branch changelog entry at `docs/changelog/<branch-name>.md`:

```markdown
# <Branch Name>

- **Date:** YYYY-MM-DD
- **Type:** feat / fix / refactor / style / docs / chore

## Summary
- Bullet points of what was built or fixed

## Technical Details (if applicable)
- New endpoints, schema changes, architecture decisions
```

**Do NOT edit shared roadmap/planning docs directly** — prevents merge conflicts between agents.

### Step 4: Stage and Commit

```bash
# Stage specific files (never git add -A)
# NEVER stage: .env, credentials, *.pem, *.key
git add <specific-files> docs/changelog/*.md

git commit -m "$(cat <<'EOF'
<type>: <description>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 5: Push and Create Staging PR

```bash
BRANCH=$(git branch --show-current)
REPO=$(grep -o '"repo"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json | head -1 | sed 's/.*"repo"[[:space:]]*:[[:space:]]*"//;s/"$//')
STAGING=$(grep -o '"staging"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json 2>/dev/null | head -1 | sed 's/.*"staging"[[:space:]]*:[[:space:]]*"//;s/"$//')
: "${STAGING:=staging}"

git push origin "$BRANCH" -u

gh pr create --repo "$REPO" \
  --base "$STAGING" --head "$BRANCH" \
  --title "<type>: <description>" --body "$(cat <<'EOF'
## Summary
<bullet points>

## Checks
- [ ] Tests pass
- [ ] Builds cleanly
- [ ] No console errors

---
Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Do NOT merge** — the user merges all PRs.

### Step 6: Create Production PR (optional)

```bash
PRODUCTION=$(grep -o '"production"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json | head -1 | sed 's/.*"production"[[:space:]]*:[[:space:]]*"//;s/"$//')
: "${PRODUCTION:=main}"

gh pr create --repo "$REPO" \
  --base "$PRODUCTION" --head "$STAGING" \
  --title "<PR title>" --body "$(cat <<'EOF'
## Summary
<bullet points>

## Test plan
- [ ] Tested in staging
- [ ] Health checks pass

---
Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Step 7: Report and Cleanup

```
Changes committed and pushed.

Staging PR: <URL>
> Review and merge when ready.

Production PR: <URL or "will create after staging merge">
> Only you can merge production PRs.
```

After PR is created, clean up the worktree:

```bash
WINDOW_ID=$(cat .claude/window-id 2>/dev/null)
MAIN_REPO=$(git rev-parse --git-common-dir | sed 's|/.git/worktrees/.*||')
cd "$MAIN_REPO"
git worktree remove "../$(basename "$MAIN_REPO")-${WINDOW_ID}" 2>/dev/null
# Remove row from .claude/active-work.md
```

## Important Notes

- **Never force push** to any branch
- **Never skip hooks** (no `--no-verify`)
- **Always create new commits** (don't amend unless explicitly asked)
- **Never merge ANY PRs** — only the user merges
- **Never use `gh pr merge`** — blocked by hooks
- **Always create a changelog entry** when shipping features
