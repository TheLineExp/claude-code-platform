---
name: shipit
description: Commits changes, pushes to staging, and creates a PR for production deployment. Use when ready to deploy changes or when the user says "ship it", "deploy", or "/shipit".
---

# Ship It Skill

This skill automates the deployment workflow: commit changes, push to staging, and create a PR for production. Works for both FM V3 and Reservations repos.

## When to Use

- When the user is ready to deploy their changes
- When the user says "ship it", "deploy", or invokes `/shipit`
- After completing a feature or fix that's ready for staging

## Prerequisites

Before running this skill, ensure:
1. All changes are tested locally
2. No build errors (`npm run build` passes)
3. **Local code review done BEFORE push (mandatory, every ship):** run `/code-review`
   on `git diff origin/staging...HEAD` and fix every finding. This is the primary
   review gate — the PR should open clean. Never skip it, never "let CI/the Actions
   reviewer catch it."
4. **Doctrine Ship Backstop done BEFORE push (Step 1b):** diff traces to the approved spec
   (no surprise features) and NO customer-contact channel (SMS/email/push/notice) was added,
   changed, or enabled without an approved spec + the user's sign-off. Backstop only — the
   real gate is letsbuild Phase 0; this just catches what slipped.

**Risk-scope the heavy checks below.** Steps 2 (traceability), 2b (action-feedback),
and 3b (test-runner scenarios) are **required for feature / UI / multi-file PRs** but
**skippable for one-line or backend-only fixes** — say which you skipped and why. The
mandatory-every-ship steps are: local code review (above), changelog entry (Step 3),
commit, and PR creation. The Actions reviewer is an opt-in safety-net, not a gate.

## Repo Detection

**Detect which repo you're in to use the correct production branch and GitHub remote:**

| Repo | Working Directory | GitHub Remote | Production Branch | Staging Branch |
|------|-------------------|---------------|-------------------|----------------|
| FM V3 | `Fleetmanager_V3` | `TheLineExp/Fleetmanager_V3` | `main` | `staging` |
| Reservations | `fleetmanager-reservations` | `TheLineExp/fleetmanager-reservations` | `master` | `staging` |

**CRITICAL: Get the production branch right. FM V3 uses `main`, Reservations uses `master`.**

## Deployment Workflow

### Step 0: Multi-Agent Pre-Flight (MANDATORY)

Before anything else, check that you're shipping safely alongside other agents:

#### Step 0a: Verify Worktree Isolation

```bash
# Confirm you're in a worktree, not the main repo
git rev-parse --git-dir
# Should show: /path/to/fleetmanager-reservations/.git/worktrees/wX (worktree)
# NOT: .git (main repo)
```

If you're in the main repo checkout (not a worktree), **STOP**: "You should be working in a worktree. Run /letsbuild first."

#### Step 0b: Conflict Pre-Check + Rebase

Check for conflicts BEFORE rebasing, so you can report them cleanly:

```bash
git fetch origin staging

# Dry-run: detect conflicts without modifying the working tree
MERGE_BASE=$(git merge-base HEAD origin/staging)
MERGE_RESULT=$(git merge-tree "$MERGE_BASE" HEAD origin/staging 2>&1)

# Check if merge-tree output contains conflict markers
if echo "$MERGE_RESULT" | grep -q "<<<<<<"; then
  # Identify which files conflict
  CONFLICT_FILES=$(echo "$MERGE_RESULT" | grep -B2 "<<<<<<" | grep "changed in both" || echo "$MERGE_RESULT" | grep "CONFLICT")
  
  # If ONLY docs/ files conflict, auto-resolve with ours strategy
  CODE_CONFLICTS=$(echo "$CONFLICT_FILES" | grep -v "docs/" | grep -v "MASTER_PLAN")
  if [ -z "$CODE_CONFLICTS" ]; then
    echo "Only documentation conflicts detected — auto-resolving with staging's version"
    git rebase origin/staging -X theirs
  else
    echo "CODE FILE CONFLICTS DETECTED:"
    echo "$CONFLICT_FILES"
    echo ""
    echo "STOP — resolve these conflicts manually before shipping."
    # Do NOT attempt to auto-resolve code conflicts
  fi
else
  # No conflicts — safe to rebase
  git rebase origin/staging
fi
```

If rebase has conflicts → **STOP** and tell the user. Don't auto-resolve code files.

#### Step 0c: Check for Conflicting Open PRs

```bash
gh pr list --repo TheLineExp/fleetmanager-reservations --base staging --state open --json number,headRefName,title --limit 10
```

If another agent has an open PR to staging, warn the user — their PR should merge first to avoid conflicts.

### Step 1: Check Current State and Branch

```bash
# Check current branch and status
git status
git branch --show-current

# Detect repo — determines production branch
basename "$(git rev-parse --show-toplevel)"
# Fleetmanager_V3 → production branch is 'main'
# fleetmanager-reservations → production branch is 'master'
```

**CRITICAL: Verify you are on a feature branch.**
- If on `staging`, `master`, or `main` → STOP. Tell the user: "Cannot ship from a protected branch. Create a feature branch first: `git checkout -b feature/w1-description`"
- If on `feature/*` → proceed
- If on any other branch → proceed with caution, warn the user

### Step 1b: Doctrine Ship Backstop (MANDATORY — fast if the plan gate was honored)

The Operating Doctrine's primary gate runs at PLANNING (letsbuild Phase 0). This is the
**backstop** — it catches only what slipped. If planning was done right, it passes in
seconds. Run `/doctrine ship-gate`:

1. **Diff ⊆ approved scope.** Skim `git diff origin/staging...HEAD`. Does every change trace
   to what the user asked for or approved? Anything extra → surface it for a quick confirm
   before shipping (don't silently ship unrequested behavior; don't hard-block obvious value
   — confirm it).
2. **Customer-contact backstop (HARD BLOCK).** Grep the diff for outbound-message surfaces:
   ```bash
   git diff origin/staging...HEAD | rg -in "sms|twilio|clicksend|sendEmail|resend|sendgrid|nodemailer|push(Notification)?|notif(y|ication)|outbound|smsNotif|emailNotif|sendMessage"
   ```
   If any customer-contact channel was **added / changed / enabled without an approved spec +
   sign-off → STOP the ship** and escalate. (Touching adjacent comms code with an approved
   spec is fine — say so.)
3. **Patch check (Rule 2).** Is this a root-cause fix or a symptom band-aid? If band-aid, fix
   the cause — don't ship the patch.

**Output:** one line — "Doctrine backstop: diff in scope, no unapproved customer-contact,
root-cause fix" — or the specific block + escalation.

### Step 2: Run Traceability Review

Before committing, verify all call chains are intact:

```
Run /traceability-review to verify end-to-end call chain integrity.
Use the traceability-reviewer agent to trace every UI action through
API client → backend route → service → database and back.
```

**If the traceability review reports CRITICAL issues, STOP and fix them before continuing.**
Major issues should be flagged to the user for a decision.

### Step 2b: Action Feedback Pattern Check

**Before committing, verify all async action handlers have proper user feedback.**

Scan all changed `.jsx` files for violations of the action feedback pattern:

```bash
# Find async handlers in changed files that only console.error without user feedback
git diff --name-only staging...HEAD -- '*.jsx' '*.tsx'
```

For each changed JSX file, use Grep to check for these **RED FLAGS**:

1. **`console.error` without `showFeedback` or `setError`** — silent failure, user gets no feedback
2. **`await` API calls in handlers without `setSavingAction` or loading state** — button can be double-clicked
3. **Data refetch calls not awaited** (e.g., `loadUser()` instead of `await loadUser()`) — race conditions

**Search patterns:**
```
# Find catch blocks that only console.error (no user feedback)
Pattern: catch.*\{[\s\S]*?console\.error[\s\S]*?\}
Check: Does the same handler also call showFeedback, setError, or setActionFeedback?

# Find async handlers without loading state
Pattern: const handle\w+ = async
Check: Does it set a loading/saving state before the API call?
```

**If violations are found:**
- **BLOCK the deployment** and list the violations
- Show file, line number, and what's missing
- Suggest specific fixes following the pattern in CLAUDE.md → "Action Feedback Pattern"

**If no violations found:** Proceed to Step 3.

### Step 3: Document Changes (Changelog Entry)

**MANDATORY — Do this BEFORE committing.**

Create a **per-branch changelog entry** instead of editing `docs/MASTER_PLAN.md` directly. This prevents merge conflicts between concurrent agents.

**File:** `docs/changelog/<branch-name>.md` (e.g., `docs/changelog/feature-w1-checkout-fix.md`)

**Contents:**

```markdown
# <Branch Name>

- **Date:** YYYY-MM-DD
- **Agent:** wX
- **Type:** feat / fix / refactor / style / docs / chore

## Summary
- Bullet points of what was built or fixed
- New capabilities delivered

## Phase Impact
- Phase XX (Name): Status change (e.g., COMPLETE, or "added sub-phase Y")
- Or: "No phase impact (bug fix / maintenance)"

## Technical Details (if applicable)
- New endpoints: POST /api/foo, GET /api/bar
- Schema changes: Added `fieldName` to `ModelName`
- New patterns or architecture decisions
```

**Do NOT edit `docs/MASTER_PLAN.md` directly** — Michael will consolidate changelog entries into the master plan periodically.

**What to document:**
- New features, sub-phases, or capabilities delivered
- Architecture decisions or new patterns introduced
- New models, schema fields, or API endpoints added

**What to skip (no changelog entry needed):**
- Pure bug fixes that restore existing behavior
- Dependency updates
- Refactors with no functional change

### Step 3b: Update Test Runner Scenarios

**MANDATORY — Do this BEFORE committing, alongside MASTER_PLAN updates.**

Every shipped feature or fix must have a verifiable test scenario in the Test Runner panel so testers can validate it in staging.

1. **Read the diff** to understand what pages/flows were added or changed
2. **Read the existing scenario data**: `c:\Users\MichaelKunz\Documents\fleetmanager\Fleetmanager_V3\frontend\src\plugins\testrunner\scenarioData.js`
3. **For each new or changed feature**, add or update a scenario entry with:
   - Unique ID (next available in the section, e.g., '1.13' for a new public flow)
   - Route patterns matching the page(s) affected
   - Step-by-step verification instructions
   - "Try to break it" edge cases
4. **Also update `docs/TEST_SCRIPT.md`** in this repo with the full scenario
5. **If the feature affects public booking or voucher portal**, also add the scenario to `bookmarklet.js` embedded data

**Generate scenarios for:** New pages, form flows, settings sections, changed behavior.
**Skip scenarios for:** Pure backend refactors, dependency updates, bug fixes restoring existing behavior.

### Step 4: Stage and Commit Changes

Stage all changes **including the changelog entry and scenarioData.js** and create a commit:

```bash
# Stage changes (prefer specific files over git add -A)
# NEVER stage: .env, credentials, prod_*.json, PROD_SECRETS_TEMP.md, nul
# ALWAYS stage: docs/changelog/*.md if a changelog entry was created
# Do NOT edit or stage docs/MASTER_PLAN.md (prevents merge conflicts)
git add <specific-files> docs/changelog/*.md

# Commit with proper format
git commit -m "$(cat <<'EOF'
<type>: <description>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

**Commit types:**
- `feat:` - New feature
- `fix:` - Bug fix
- `refactor:` - Code refactoring
- `style:` - CSS/styling changes
- `docs:` - Documentation
- `chore:` - Maintenance tasks

### Step 5: Push Feature Branch and Create Staging PR

**Branch protection is enabled on staging — direct push is blocked. Use a PR.**

```bash
# Push the feature branch to remote
git push origin <feature-branch> -u

# Create PR to staging
# FM V3
gh pr create --repo TheLineExp/Fleetmanager_V3 \
  --base staging --head <feature-branch> \
  --title "<type>: <description>" --body "$(cat <<'EOF'
## Summary
<bullet points of changes>

## Checks
- [ ] Backend tests pass
- [ ] Frontend builds
- [ ] No console errors

---
Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

# Reservations
gh pr create --repo TheLineExp/fleetmanager-reservations \
  --base staging --head <feature-branch> \
  --title "<type>: <description>" --body "$(cat <<'EOF'
## Summary
<bullet points of changes>

## Checks
- [ ] Backend tests pass
- [ ] Frontend builds
- [ ] No console errors

---
Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Wait for CI checks to pass, then **report the PR as a clickable link with its verified live state** — `[TheLineExp/<repo>#<n>](<url>) — OPEN → staging (needs your merge)`, state checked via `gh pr view <n> --repo <owner/repo> --json state,baseRefName,url,mergedAt` right before writing. Do NOT merge — the user merges all PRs (both staging and production), so make the "needs your merge" link obvious and never make the user hunt for it.

```bash
# Check PR status
gh pr checks <pr-number>
```

Once the user merges, staging auto-deploys (~3-5 minutes). Verify the deploy completes:

```bash
# FM V3
gh run list --repo TheLineExp/Fleetmanager_V3 --branch staging --limit 1

# Reservations
gh run list --repo TheLineExp/fleetmanager-reservations --branch staging --limit 1
```

### Step 6: Create Production PR

**IMPORTANT: Only CREATE the PR. Never merge it — the user merges production PRs manually.**

```bash
# FM V3 — PR targets 'main'
gh pr create --repo TheLineExp/Fleetmanager_V3 \
  --base main --head staging \
  --title "<PR title>" --body "$(cat <<'EOF'
## Summary
<bullet points of changes>

## Test plan
- [ ] Tested locally
- [ ] Tested in staging
- [ ] No console errors
- [ ] Health checks pass after deploy

---
Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

# Reservations — PR targets 'master' (NOT main!)
gh pr create --repo TheLineExp/fleetmanager-reservations \
  --base master --head staging \
  --title "<PR title>" --body "$(cat <<'EOF'
## Summary
<bullet points of changes>

## Test plan
- [ ] Tested locally
- [ ] Tested in staging
- [ ] No console errors
- [ ] Health checks pass after deploy

---
Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

If a PR already exists (staging→main or staging→master), tell the user it's already open and provide the URL.

### Step 7: Report Staging PR URL

Return the staging PR URL to the user. The user will:
1. Review the PR diff
2. Merge it (regular merge, NOT squash — preserves commit history)
3. Staging auto-deploys after merge

**Do NOT attempt `gh pr merge` — this is blocked by hooks.**

### Step 8: Create Production PR (after staging merge)

After the user confirms staging is merged and healthy, create the production PR (or note if one already exists). Return the production PR URL.

**Do NOT attempt to merge the production PR.**

## Important Notes

- **Never force push** to staging, main, or master
- **Never skip hooks** (no `--no-verify`)
- **Always create new commits** (don't amend unless explicitly asked)
- **Never merge ANY PRs** — only the user merges PRs (both staging and production). Agents create PRs and report URLs.
- **Never use `gh pr merge`** — this is blocked by hooks. Always use `gh pr create` only.
- **Never use `--admin` flag** (bypasses branch protections)
- **Always create a changelog entry** in `docs/changelog/` when shipping features (do NOT edit MASTER_PLAN.md directly)
- PR required for production — direct push to main/master is not allowed
- Staging auto-deploys on push (~3-5 minutes)
- Production deploys after the user merges the PR
- Database migrations run automatically as part of the deploy pipeline (migrate job)

## CI/CD Pipeline (both repos)

The deploy pipeline runs these jobs in order:
1. **Setup** — determine environment from branch (staging vs production)
2. **Pre-deploy Tests** — unit tests + frontend build check
3. **Build Images** — Docker build + push to `fleetmanageracr.azurecr.io`
4. **Deploy Backend** — update Azure Container App + health check
5. **Deploy Frontend** — update Azure Container App + health check
6. **Database Migrations** — 3-step idempotent pipeline:
   - `repair-migrations.js` — sync checksums + detect/fix drift
   - `npx prisma migrate deploy` — apply pending migrations (all SQL is idempotent)
   - `verify-schema.js` — verify 123 canary checks pass
7. **Summary** — print deployment URLs

All migrations use IF NOT EXISTS / IF EXISTS guards. No more baselining, retry loops, or failure cascading. Skip migrations with `skip_migrations: true` in workflow dispatch.

## Output Format

After completing, report:

```
Changes committed and pushed to feature branch.
Local /code-review run on the diff before push; findings fixed.

Staging PR: [TheLineExp/<repo>#<n>](<PR URL>) — OPEN → staging (needs your merge)
> Review and merge when ready. Use regular merge (NOT squash) to preserve commit history.
> Staging auto-deploys ~5 minutes after merge.

Staging URL: <appropriate staging URL>

Production PR: [TheLineExp/<repo>#<n>](<PR URL>) — OPEN → master/main (needs your merge)  [or "will create after staging merge"]
> Only you can merge production PRs.
```

**Staging URLs:**
- FM V3: https://fleetmanager-web-staging.proudriver-28095095.westus2.azurecontainerapps.io
- Reservations: https://reservations-web-staging.proudriver-28095095.westus2.azurecontainerapps.io

**Production URLs:**
- FM V3: https://fleetmanager-web-prod.blackmeadow-d39ebc45.westus2.azurecontainerapps.io
- Reservations: https://reservations-web-prod.blackmeadow-d39ebc45.westus2.azurecontainerapps.io

**Health check URLs:**
- FM V3: `<base>/api/health`
- Reservations: `<base>/health`

## Step 9: Worktree Cleanup (after PR created)

After the staging PR is created and CI passes, clean up the worktree:

```bash
WINDOW_ID=$(cat .claude/window-id 2>/dev/null)
BRANCH=$(git branch --show-current)
MAIN_REPO="c:/Users/MichaelKunz/Documents/fleetmanager-reservations"

# Switch to main repo for cleanup commands
cd "$MAIN_REPO"

# Remove the worktree
git worktree remove "../fleetmanager-reservations-${WINDOW_ID}" 2>/dev/null

# Remove the active-work.md registration
# (edit .claude/active-work.md to remove this agent's row)
```

**Do NOT delete the local branch or remote branch yet** — the PR needs them until it's merged.

After the user merges the PR:
```bash
# Delete local branch
git branch -d "$BRANCH"

# Delete remote branch
git push origin --delete "$BRANCH"
```

Tell the user: "Worktree cleaned up. Open a new Claude Code window at the main repo for your next task."

## Error Handling

- **Uncommitted changes in staging**: Stash or commit them first
- **Merge conflicts**: Resolve manually before continuing
- **PR already exists**: Update existing PR or link to it
- **Push rejected**: Pull latest changes and retry
- **Deploy fails**: Check `gh run view <id>` for details, check container logs with `az containerapp logs show`

## Deployment Order (when shipping multiple repos)

If changes span multiple repos, deploy in this order:
1. **Vouchers first** (if involved) — backend service endpoints other repos depend on
2. **Reservations second** — depends on Voucher API, provides API for FM V3 frontend
3. **FM V3 last** — frontend depends on both Reservations and Voucher APIs

## Cross-Repo Shipping Mode

**Detection:** Read `.claude/window-id` — if it starts with `x`, this is a cross-repo feature.

When in cross-repo mode, `/shipit` must handle multiple repos in a single session:

### Step 0x: Identify Affected Repos

```bash
# Check which repos have changes on the cross-repo branch
XREF=$(cat .claude/window-id | tr -d '[:space:]')
BRANCH="feature/${XREF}-*"  # the branch slug

REPOS=(
  "c:/Users/MichaelKunz/Documents/fleetmanager-vouchers|TheLineExp/fleetmanager-vouchers"
  "c:/Users/MichaelKunz/Documents/fleetmanager-reservations|TheLineExp/fleetmanager-reservations"
  "c:/Users/MichaelKunz/Documents/fleetmanager/Fleetmanager_V3|TheLineExp/Fleetmanager_V3"
)

for ENTRY in "${REPOS[@]}"; do
  REPO_PATH="${ENTRY%%|*}"
  REPO_REMOTE="${ENTRY##*|}"
  cd "$REPO_PATH"

  # Find the cross-repo branch in this repo
  ACTUAL_BRANCH=$(git branch --list "feature/${XREF}-*" --format="%(refname:short)" | head -1)
  if [ -n "$ACTUAL_BRANCH" ]; then
    git checkout "$ACTUAL_BRANCH"
    CHANGES=$(git diff staging --name-only 2>/dev/null | wc -l)
    if [ "$CHANGES" -gt 0 ]; then
      echo "CHANGES: $REPO_REMOTE on $ACTUAL_BRANCH ($CHANGES files)"
    fi
  fi
done
```

### Cross-Repo PR Creation

Create PRs in **deployment order** (Vouchers → Reservations → FM V3). Each PR body cross-references the others:

```bash
# After creating each PR, collect the PR numbers
PR_URLS=()

for each repo with changes (in deployment order):
  cd <repo working dir — worktree or main checkout>

  # Stage, commit, push (same as single-repo Steps 3-5)
  git add <files>
  git commit -m "<type>: <description>

  Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
  git push origin "$BRANCH" -u

  # Create PR with cross-references
  gh pr create --repo <GITHUB_REMOTE> \
    --base staging --head "$BRANCH" \
    --title "<type>: <description>" --body "$(cat <<EOF
## Summary
<bullet points>

## Cross-Repo Feature: <feature name>
Related PRs:
$(for URL in "${PR_URLS[@]}"; do echo "- $URL"; done)

**Deploy order:** Vouchers → Reservations → FM V3

## Checks
- [ ] Backend tests pass
- [ ] Frontend builds (if applicable)
- [ ] No console errors

---
Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

  PR_URLS+=("$(gh pr view --repo <GITHUB_REMOTE> --json url -q .url)")
done
```

**After all PRs are created:** Go back and update the FIRST PR's body to include links to the later PRs (since they didn't exist yet when it was created).

### Cross-Repo Cleanup

After all PRs are created:

```bash
for each affected repo:
  cd <REPO_PATH>

  # Remove worktree if one exists
  git worktree remove "../<repo-name>-${XREF}" 2>/dev/null
  git worktree prune

  # Remove active-work.md registration
  # (edit .claude/active-work.md to remove this agent's row)

  # Reset window-id if it was set to xN
  WID=$(cat .claude/window-id 2>/dev/null | tr -d '[:space:]')
  if [[ "$WID" == x* ]]; then
    echo "setup" > .claude/window-id
  fi
done
```

### Cross-Repo Output Format

```
Cross-repo feature shipped!

Staging PRs (in deployment order):
  1. Vouchers: <PR URL>
  2. Reservations: <PR URL>
  3. FM V3: <PR URL>

> Merge in this order: Vouchers → Reservations → FM V3
> Each merge triggers auto-deploy to staging (~5 min each).
> Wait for each deploy to complete before merging the next.

Production PRs: will create after all staging PRs are merged and verified.
```

## Post-Deploy Verification

After the user merges and production deploys:

```bash
# FM V3
curl -s https://fleetmanager-api-prod.blackmeadow-d39ebc45.westus2.azurecontainerapps.io/api/health
# Expected: {"success":true,"message":"The Line Fleet Manager API is running",...}

# Reservations
curl -s https://reservations-api-prod.blackmeadow-d39ebc45.westus2.azurecontainerapps.io/health
# Expected: {"status":"ok","service":"fleetmanager-reservations","environment":"production",...}
```
