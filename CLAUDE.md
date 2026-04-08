# {{PROJECT_NAME}} — Development Guide

## Quick Reference

### Development Workflow
```
/letsbuild  →  develop  →  /pre-deploy  →  /shipit
```

### Critical Rules

**DO NOT:**
- Commit directly to protected branches ({{PROTECTED_BRANCHES}})
- Skip hooks with `--no-verify`
- Force push to any branch
- Merge PRs as an agent — only the user merges
- Work in the main repo checkout — use worktrees

**ALWAYS:**
- Run `/letsbuild` before starting any work
- Work in your assigned worktree directory
- Register your branch in `.claude/active-work.md`
- Run tests before committing
- Create PRs instead of pushing to protected branches

---

## Multi-Agent Workflow (Enforced by Hooks)

### Branch Rules

**MANDATORY: Run `/letsbuild` before starting ANY work.** This creates an isolated git worktree so agents can't overwrite each other.

### Worktree Architecture

```
{{REPO_DIR}}/          # main repo ({{STAGING_BRANCH}} — setup only, NEVER code here)
{{REPO_DIR}}-w1/       # agent window 1 worktree
{{REPO_DIR}}-w2/       # agent window 2 worktree
{{REPO_DIR}}-w3/       # agent window 3 worktree
```

### Branch Naming

`{{FEATURE_PREFIX}}<window>-<slug>` — e.g., `{{FEATURE_PREFIX}}w1-add-login`

### Post-Plan Execution Rule

When exiting plan mode to begin implementation:
1. Check: Am I in a worktree? (`git rev-parse --git-dir` should contain `/worktrees/`)
2. If NOT → Run `/letsbuild` BEFORE making any code changes
3. If YES → Verify registration in `active-work.md`, then proceed

### Merge Flow

1. Feature branch → PR to {{STAGING_BRANCH}} (agent creates PR)
2. {{STAGING_BRANCH}} → {{PRODUCTION_BRANCH}} via PR (only user merges)
3. Agents NEVER merge ANY PRs

---

## Effort Level Management

Match your effort level to the task:

| Task | Effort | Model |
|------|--------|-------|
| Architecture / system design | `/effort high` | opus |
| Complex debugging | `/effort high` | opus |
| New feature implementation | `/effort high` | opus |
| Simple bug fix | `/effort medium` | sonnet |
| Test writing | `/effort medium` | sonnet |
| Documentation | `/effort low` | sonnet |
| Git operations | `/effort low` | sonnet |

For mixed sessions: `/model opusplan` (Opus for planning, Sonnet for execution).

---

## Session Conservation

- After ~50 tool calls, consider wrapping up or committing progress
- After ~80 tool calls, suggest opening a new window for the next task
- When context compaction occurs, alert the user and recommend a fresh session
- Don't retry failed operations — if something fails twice, ask the user

---

## Error Handling — One Try Rule

When a tool call fails:
1. Read the error carefully
2. If it's a configuration error, attempt ONE fix
3. If the fix doesn't work, **STOP and tell the user** — don't loop
4. Never retry the exact same command that just failed

---

## Configuration

Project settings are in `platform.config.json`. Read it for:
- Branch names, feature prefixes, owner prefixes
- Test commands and runners
- Deployment URLs and health endpoints
- Security patterns

---

## Project-Specific Rules

Add your project-specific rules below. These override the generic platform rules.

### Customization

To add project-specific checks to platform skills, create addon files:
- `.claude/code-review-addons.md` — extra code review checks
- `.claude/security-review-addons.md` — security requirements
- `.claude/api-review-addons.md` — API design patterns
- `.claude/pre-deploy-addons.md` — deployment checks
- `.claude/perf-test-addons.md` — performance thresholds
- `.claude/deploy-verifier-addons.md` — post-deploy verification

### Project Rules

<!-- Add your project-specific rules here -->

---

## Debugging

```bash
# Check health
curl -s {{STAGING_URL}}{{HEALTH_ENDPOINT}}

# View logs
# (add your log viewing commands here)

# Check CI
gh run list --repo {{GITHUB_REPO}} --limit 5
```
