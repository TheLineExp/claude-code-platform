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
4. **Adversarial Parity Sweep done BEFORE push (Step 1b)** for any payment/refund/voucher,
   state-transition, shared-helper, auth-gate, or concurrency change. `/code-review` reasons
   about the diff on the happy path; it cannot see the sibling call site, parallel surface,
   extra exit branch, or twin route where these bugs actually live — which is why they keep
   coming back across 2–4 review rounds. Step 1b reads the whole surface. Not skippable for
   those change types, including backend-only one-liners.
5. **Doctrine Ship Backstop done BEFORE push (Step 1c):** diff traces to the approved spec
   (no surprise features) and NO customer-contact channel (SMS/email/push/notice) was added,
   changed, or enabled without an approved spec + Mike's sign-off. Backstop only — the real
   gate is letsbuild Phase 0; this just catches what slipped.

**Risk-scope the heavy checks below.** Steps 2 (traceability), 2b (action-feedback),
and 3b (test-runner scenarios) are **required for feature / UI / multi-file PRs** but
**skippable for one-line or backend-only fixes** — say which you skipped and why.
**Step 1b (Adversarial Parity Sweep) is the exception: it is scoped by change TYPE, not
size.** It is required — never skippable — for any payment/refund/voucher, state-transition,
shared-helper, auth-gate, or concurrency change, *including backend-only one-liners*, because
that is exactly where the recurring multi-round bugs live. The mandatory-every-ship steps are:
local code review + Step 1b where it applies (above), changelog entry (Step 3), commit,
**outside-lens review (Step 4b — context-isolated, every ship, no size exemption)**, and PR
creation. The Actions reviewer is an opt-in safety-net, not a gate.

## Repo Detection

**Detect which repo you're in to use the correct production branch and GitHub remote:**

| Repo | Working Directory | GitHub Remote | Production Branch | Staging Branch |
|------|-------------------|---------------|-------------------|----------------|
| FM V3 | `Fleetmanager_V3` | `TheLineExp/Fleetmanager_V3` | `main` | `staging` |
| Reservations | `fleetmanager-reservations` | `TheLineExp/fleetmanager-reservations` | `master` | `staging` |
| Vouchers | `fleetmanager-vouchers` | `TheLineExp/fleetmanager-vouchers` | `master` | `staging` |

**CRITICAL: Get the production branch right. FM V3 uses `main`; Reservations and Vouchers use `master`.**

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

### Step 1b: Adversarial Parity Sweep (MANDATORY for payment / state / shared / auth / concurrency changes)

This is the gate that catches what `/code-review`'s diff scope cannot: **bugs in code you did
NOT change.** Across the last ~250 external-reviewer findings, ~65% were one defect — a change
that is locally correct but inconsistent with a sibling site it didn't touch — and most of the
rest were concurrency interleavings or unhandled sub-cases. A diff-scoped, happy-path review
cannot see any of them. **Required, never skippable** (even for a backend one-liner) whenever
the diff touches: refunds/payments/vouchers/Stripe, a status or state transition, a shared
helper or serializer, an auth/role gate, or anything concurrent. (Pure cosmetic/copy/CSS may
skip it — say so.)

**Run the sweep as agents, not prose.** Launch BOTH (in parallel, via the Agent tool):
1. **`parity-sweep` agent** — covers Part 1 and Part 3 below (sibling call sites, twin
   surfaces, config/deploy surfaces, legacy data, stale tests). Give it the branch + base.
2. **`money-concurrency-reviewer` agent** — covers Part 2 below whenever the diff touches
   payments/refunds/vouchers/Stripe/webhooks/balances/locks/state machines. Give it the
   branch + base; it reads whole call chains on the FINAL HEAD.

A sweep report with no CHECKED-CLEAN entries, or any BLOCK verdict, **blocks the ship** —
fix and re-run. The checklists below define what the agents must cover (and are the manual
fallback if agents are unavailable). Optionally use graphify for reverse blast radius if the
graph is fresher than HEAD (`graphify update . --force` is free).

**RE-REVIEW RULE (fix-the-fix killer):** every time you address review findings (yours,
Codex's, or Mike's), re-run BOTH agents on the NEW HEAD before pushing the fix round —
AND re-run **`outside-reviewer`** (Step 4b) on the fix commits: every Codex round today
receives unreviewed fix commits, which is exactly how one fix PR took 8 external review
rounds. A fix round is a new diff and gets the full gate before it leaves the machine.

**Part 1 — Parity sweep (cross-site consistency).** For each symbol/route/flag/derived-value/guard/contract in the diff:
```bash
# every consumer of a symbol/helper you changed — are they ALL consistent with the new behavior?
rg -n "<symbolOrHelperName>" backend/src frontend/src
# twin-route parity: does the org↔distributor / staff↔public sibling exist AND carry the same gate?
rg -n "<routePath>|requireRole|isManagerForFleet|requirePartnerRole" backend/src/routes
# flag threaded through the WHOLE chain (not just the entry gate)?
rg -n "allowClosedDays|mode:\s*'STAFF'|readOnly" backend/src
# migration registered in BOTH canaries?
rg -n "<migration_name>" backend/scripts/verify-schema.js backend/scripts/repair-migrations.js
# any test still asserting the OLD shape/value?
rg -n "<oldValueOrHeadingOrField>" -g '*.test.*'
```
RED FLAGS → BLOCK: a derived value (displayStatus, fleet-tz time, `waiverSigned`) rendered raw
on a parallel surface; a flag set at one gate but re-rejected by a downstream sibling; a new
route whose twin lacks the role gate; a client sending a field/route the server doesn't
consume/expose; a migration missing from a canary; a test asserting the pre-change shape.

**Part 2 — Adversarial state / concurrency.** For payment/state-machine/shared-mutable code, write the answer to each:
- For EACH exit branch of the changed function, what value does it read or RESTORE — and is it
  stale if a second request ran concurrently? (refund lock-release-to-stale-status, over-issue TOCTOU.)
- Is every read of mutable balance/status/idempotency INSIDE the lock? Nothing read before the
  lock that's used after it.
- Is the idempotency key unique per logical operation AND written atomically under the lock?
- After any reorder/refactor: diff the GUARD SET — did `amountCents<=0`, a status-in-set check,
  or similar get dropped or bypassed? Re-derive the whole state machine; do NOT patch only the
  reported symptom.
BLOCK on any "it's stale / not under the lock / a guard moved."

**Part 3 — Edge / sub-case / trust-boundary.** Enumerate explicitly (don't assume the common case):
- Sub-cases under every new default/branch: no-payment, $0/negative, authorized-vs-captured,
  already-refunded/returned, empty/single-element, reversed/zero-length window.
- Trust-boundary inputs: string query/form flags parsed explicitly (NOT `Boolean(req.query.x)` —
  `'false'` is truthy); fetched URLs canonicalized + private-range-blocked + byte-bounded (SSRF);
  a new mutation/delivery route copies the adjacent route's auth gate.
BLOCK on any unhandled sub-case or unguarded boundary input.

**Output:** list what you swept, found, and fixed — e.g. "Parity: checked 3 consumers of
`computeRefundable`, fixed month-serializer rendering raw status. Concurrency: moved
`alreadyRefundedCents` read inside the lock. Edge: added no-payment + $0 guards." If you
genuinely skipped this step, state which change type made it safe to skip.

### Step 1c: Doctrine Ship Backstop (MANDATORY — fast if the plan gate was honored)

The Operating Doctrine's primary gate runs at PLANNING (letsbuild Phase 0). This is the
**backstop** — it catches only what slipped through. If planning was done right, it passes
in seconds. Run `/doctrine ship-gate`:

1. **Diff ⊆ approved scope.** Skim `git diff origin/staging...HEAD`. Does every change trace
   to what Mike asked for or approved? Anything extra → surface it to Mike for a quick
   confirm before shipping. (Don't silently ship unrequested behavior; don't hard-block
   obvious value — confirm it.)
2. **Customer-contact backstop (HARD BLOCK).** Grep the diff for outbound-message surfaces:
   ```bash
   git diff origin/staging...HEAD | rg -in "sms|twilio|clicksend|sendEmail|resend|sendgrid|nodemailer|push(Notification)?|notif(y|ication)|outbound|smsNotif|emailNotif|sendMessage"
   ```
   If any customer-contact channel was **added / changed / enabled without an approved spec +
   Mike's sign-off → STOP the ship** and escalate. This is the gate that would have caught the
   feedback-SMS. (Touching adjacent comms code with an approved spec is fine — say so.)
3. **Patch check (Rule 2).** Is this a root-cause fix or a symptom band-aid? If band-aid,
   it's not ready — fix the cause, don't ship the patch.

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
2. **Read the existing scenario data**: `"/Users/mikekunz/Documents/Volo Technologies/Fleetmanager_V3/frontend/src/plugins/testrunner/scenarioData.js"`
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

Co-Authored-By: Claude <noreply@anthropic.com>
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

### Step 4b: Outside-Lens Review (MANDATORY, every ship — after commit, BEFORE push)

The reviews so far ran in YOUR context — the same mental model that wrote the code. Codex's
edge is that it has none of that context; this step gives you the same edge locally, so
Codex converges in ≤1 round instead of 4–8.

Spawn the **`outside-reviewer` agent** on the final commit. **Context isolation is the
mechanism — its inputs are EXHAUSTIVELY these two, nothing else:**
1. the branch + base (it runs `git diff origin/staging...HEAD` itself),
2. the PR title/description you're about to use (the spec, as an outsider reads it).

NOTHING about how the change was developed, what you already checked, or what you believe
is safe — adding "helpful context" to its prompt is how the isolation erodes. Do not defend
findings by citing session context the reviewer can't see — if the code doesn't prove it,
Codex would flag it too.

Then:
1. **PASS** (all 7 families checked-clean) → proceed to Step 5.
2. **FINDINGS** → fix every P1 (P2s: fix or carry a written rationale into the PR
   description), commit, and **re-run the agent on the new HEAD** — fix rounds introduce
   new bugs (the fix-the-fix pattern: one fix PR took 8 external rounds).
3. Cap: if findings persist after 2 fix rounds, STOP — do not push. Surface the remaining
   findings to Mike; repeated non-convergence means the change needs a rethink, not a
   round 3 (doctrine rule 3).

The scoped agents (Step 1b) still run per their triggers — outside-reviewer is the
general-diff layer covering every ship, including the diffs Step 1b doesn't gate.

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

### Step 5b: PR-Ready Gate (MANDATORY before ANY "ready / done / shipped" claim)

Never report a PR as ready from memory — a stale "ready" report is a defect. **Immediately
before** the words "ready", "done", or "shipped" leave your mouth, verify LIVE state:

```bash
# 1. All checks green
gh pr checks <n> --repo <owner/repo>

# 2. Zero unresolved review threads (Codex comments live here — this is the query that finds them)
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100) {
        nodes { isResolved isOutdated path line comments(first:1){nodes{author{login} body}} }
      }
    }
  }
}' -f owner=<owner> -f repo=<repo> -F pr=<n> \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false)] | length'
```

**BLOCK the "ready" report** if any check is failing or the unresolved-thread count is > 0:
address every unresolved thread (fix + reply, or justify and resolve), re-run the Step 1b
agents AND the `outside-reviewer` (Step 4b) on the new HEAD (RE-REVIEW RULE), push, and
re-check. Only a live result of "checks green + 0 unresolved threads" earns the word "ready".

To reply to an inline review thread, use the WORKING recipe (do not guess payload shapes):
```bash
# reply to an existing inline comment (needs the comment's numeric id from /pulls/<n>/comments)
gh api repos/<owner>/<repo>/pulls/<n>/comments/<comment_id>/replies -f body="Fixed in <sha>: <what changed>"
```

Once the user merges, staging auto-deploys (~3-5 minutes). Verify the deploy completes:

```bash
# FM V3
gh run list --repo TheLineExp/Fleetmanager_V3 --branch staging --limit 1

# Reservations
gh run list --repo TheLineExp/fleetmanager-reservations --branch staging --limit 1
```

### Step 6: Create Production PR

**PROD-PROMOTION GATE (MANDATORY — kills the double-review furnace).** Do NOT create the
production PR until the staging PR(s) feeding it are CONVERGED. Two weeks of data show 14+
prod PRs re-flagged with the *same or new* findings because staging fixes weren't finished
before promotion — every one of those doubled the review cost. Verify, live:

1. **Every staging PR in this release is merged AND had 0 unresolved review threads at merge**
   (Step 5b query, run against each staging PR). If Codex flagged something on staging, the
   fix must be merged to staging BEFORE the prod PR exists — never "fix it on the prod PR."
2. **No open staging PRs** that overlap the same files (`gh pr list --base staging --state open`).
3. If a finding was consciously NOT fixed, that needs Mike's explicit OK, in writing, per
   doctrine Rule 4 — a deferred P1/P2 on a prod release is shipped, not deferred.

Only after all three pass, create the prod PR.

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
REPO_NAME=$(basename "$(git worktree list | head -1 | awk '{print $1}')")
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')   # first entry is always the main checkout

# Switch to main repo for cleanup commands (quote — path contains a space)
cd "$MAIN_REPO"

# Remove the worktree
git worktree remove "../${REPO_NAME}-${WINDOW_ID}"

# Remove the active-work.md registration
# (edit .claude/active-work.md to remove this agent's row)

# GC pass: remove ALL other worktrees whose branch is merged and tree is clean
# (git worktree remove refuses dirty trees — that refusal is the safety; never --force here)
git worktree list --porcelain | awk '/^worktree /{print $2}' | tail -n +2 | while read -r WT; do
  WTBRANCH=$(git -C "$WT" branch --show-current)
  if [ -n "$WTBRANCH" ] && git merge-base --is-ancestor "$WTBRANCH" origin/staging 2>/dev/null; then
    git worktree remove "$WT" 2>/dev/null && echo "GC'd merged worktree: $WT"
  fi
done
git worktree prune
```

**Do NOT delete the local branch or remote branch yet** — the PR needs them until it's merged.

After the user merges the PR:
```bash
# Delete local branch
git branch -d "$BRANCH"

# Delete remote branch
git push origin --delete "$BRANCH"
```

Tell the user: "Worktree cleaned up. **This session's feature is shipped — end this session
now** and start the next task in a fresh window (`/letsbuild` there). One feature per session:
marathon sessions burn context, hit compaction, and produce stale state."

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
  "/Users/mikekunz/Documents/Volo Technologies/fleetmanager-vouchers|TheLineExp/fleetmanager-vouchers"
  "/Users/mikekunz/Documents/Volo Technologies/fleetmanager-reservations|TheLineExp/fleetmanager-reservations"
  "/Users/mikekunz/Documents/Volo Technologies/Fleetmanager_V3|TheLineExp/Fleetmanager_V3"
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

  Co-Authored-By: Claude <noreply@anthropic.com>"
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
