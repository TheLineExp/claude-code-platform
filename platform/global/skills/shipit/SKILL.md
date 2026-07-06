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

### Step 1a: Mechanical Pre-Flight Guards (cheap, always run)

Three audit failure classes had NO mechanical guard — they relied on the model noticing.
These are cheap greps; run them and report what fired. (The judgment-level versions live in
the `outside-reviewer` families 3/6 — this is the mechanical floor under them.)

```bash
BASE=origin/staging   # base you're shipping against

# 1. GIANT-PR SIZE — oversized diffs hide bugs and blow review budgets (doctrine: split it).
LINES=$(git diff $BASE...HEAD --numstat | awk '{a+=$1;d+=$2} END{print a+d+0}')
FILES=$(git diff $BASE...HEAD --name-only | wc -l | tr -d ' ')
echo "diff size: $LINES lines across $FILES files"
{ [ "$LINES" -gt 600 ] || [ "$FILES" -gt 25 ]; } && \
  echo ">>> GIANT PR — recommend splitting; if shipping whole, say WHY in the PR body"

# 2. REPEAT-OFFENDER (root-defect re-patched across PRs) — a file fixed again and again is a
#    symptom of an unfixed root cause. Find the PRIOR fix before adding another patch.
for f in $(git diff $BASE...HEAD --name-only | grep -vE '^docs/|changelog|\.md$'); do
  n=$(git log --oneline --since='45 days ago' -- "$f" | grep -ciE '\b(fix|hotfix|bug)\b')
  [ "$n" -ge 3 ] && echo ">>> REPEAT-OFFENDER: $f — $n fix-commits/45d; are you re-patching a root defect?"
done

# 3. KNOWN-HELPERS-IGNORED (heuristic — candidates to eyeball, not hard blocks). Hand-rolled
#    logic where a documented helper exists. Confirm each hit against outside-reviewer family 6.
git diff $BASE...HEAD | rg -n '^\+' | rg -in \
  -e 'error\.response\.data|err\.message.*toast|catch\s*\([^)]*\)\s*\{[^}]*setError' \
  -e '\|\|\s*(0|\[\]|\{\})\b' \
  -e '\.(mutate|mutateAsync)\(' \
  && echo ">>> KNOWN-HELPERS candidates — verify: apiErrorText for errors, ?? not || on intentional 0/[], React-Query invalidate after each mutation"
```

Report one line: sizes, any repeat-offenders, any helper candidates — or "pre-flight clean".
None of these HARD-block by themselves; a giant PR or repeat-offender that ships anyway needs
a one-line justification in the PR body (doctrine Rule 1 — flag loudly, then proceed).

### Step 1b: Adversarial Parity Sweep (MANDATORY for payment / state / shared / auth / concurrency changes)

This is the gate that catches what `/code-review`'s diff scope cannot: **bugs in code you did
NOT change.** Across the last ~250 external-reviewer findings, ~65% were one defect — a change
that is locally correct but inconsistent with a sibling site it didn't touch — and most of the
rest were concurrency interleavings or unhandled sub-cases. A diff-scoped, happy-path review
cannot see any of them. **Required, never skippable** (even for a backend one-liner) whenever
the diff touches: refunds/payments/vouchers/Stripe, a status or state transition, a shared
helper or serializer, an auth/role gate, or anything concurrent. (Pure cosmetic/copy/CSS may
skip it — say so.)

**Mechanical trigger (run FIRST — do not decide scope by judgment alone).** Model-judgment
misclassifies "is this a money/state change?" and then the gate silently never fires. Grep the
diff the same way the doctrine ship-gate greps for customer-contact — if ANY line matches, Step
1b is REQUIRED and not skippable:
```bash
git diff origin/staging...HEAD | rg -in \
  -e 'refund|payment|stripe|webhook|charge|payout|settl|voucher|balance|invoice|amount(Cents)?|price|deposit' \
  -e 'prisma\.\w+\.(update|updateMany|upsert|delete|deleteMany|create)|\$executeRaw|\$queryRaw' \
  -e 'status\s*[:=]|\btransition|CONFIRMED|CANCELL|PENDING|\bACTIVE\b|REFUND|CAPTUR|VOID' \
  -e 'authenticate|authoriz|requireRole|requirePartnerRole|isManagerForFleet|optionalAuth' \
  -e '\$transaction|advisory_?lock|idempoten|mutex|withLock|_withSettlementLock' \
  && echo ">>> Step 1b REQUIRED — money/state/writer/auth/concurrency signal in diff"
```
A hit = mandatory (launch the agents below). No hit does NOT auto-exempt: a shared
helper/serializer rename won't match, so still eyeball the diff — but a hit removes all
discretion. Say in your ship output whether the grep fired and which pattern class.

**Run the sweep as agents, not prose.** Launch BOTH (in parallel, via the Agent tool):
1. **`parity-sweep` agent** — covers Parts 1 and 3 of `reference/parity-gate.md` (sibling call
   sites, twin surfaces, config/deploy surfaces, legacy data, stale tests). Give it branch + base.
2. **`money-concurrency-reviewer` agent** — covers Part 2 of `reference/parity-gate.md` whenever
   the diff touches payments/refunds/vouchers/Stripe/webhooks/balances/locks/state machines. Give
   it the branch + base; it reads whole call chains on the FINAL HEAD.

A sweep report with no CHECKED-CLEAN entries, or any BLOCK verdict, **blocks the ship** —
fix and re-run. **The full sweep checklist (Parts 1–3) is in `reference/parity-gate.md`** — it
defines what the agents must cover and is the manual fallback if agents are unavailable.
Optionally use graphify for reverse blast radius if the graph is fresher than HEAD
(`graphify update . --force` is free).

**RE-REVIEW RULE (fix-the-fix killer):** every time you address review findings (yours,
Codex's, or Mike's), re-run BOTH agents on the NEW HEAD before pushing the fix round —
AND re-run **`outside-reviewer`** (Step 4b) on the fix commits: every Codex round today
receives unreviewed fix commits, which is exactly how one fix PR took 8 external review
rounds. A fix round is a new diff and gets the full gate before it leaves the machine.

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
mechanism — the PROMPT you hand it contains EXHAUSTIVELY these two things, nothing else:**
1. the branch + base (it runs `git diff origin/staging...HEAD` itself),
2. the PR title/description you're about to use (the spec, as an outsider reads it).

This is what you PASS IN — not a limit on what it may READ. The agent has full repo access
and must open unchanged callers/siblings/configs itself (that's where the parity bugs live);
Codex sees the whole repo too. What it never gets is the authoring narrative: NOTHING about
how the change was developed, what you already checked, or what you believe is safe — adding
"helpful context" to its prompt is how the isolation erodes. Do not defend findings by citing
session context the reviewer can't see — if the code doesn't prove it,
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

Never report a PR as ready from memory — a stale "ready" report is a defect. This gate is a
REAL control, not prose: run the verifier, which checks LIVE state and writes a freshness
marker. The `Stop` hook (`pr-ready-gate.js` with no args) BLOCKS a "ready/done/shipped" claim
about a PR that has no fresh PASS marker — so skipping this step is caught automatically.

```bash
# Runs `gh pr checks` + the unresolved-review-thread count; writes a PASS marker (valid 20 min)
# ONLY on "checks green + 0 unresolved". Prints PR-READY VERIFIED (exit 0) or BLOCKED (exit 1).
node ~/.claude/hooks/pr-ready-gate.js verify <owner/repo> <n>
```

Only after it prints **PR-READY VERIFIED** may you use the word "ready". If it BLOCKS, do NOT
report ready — fix, push, re-verify. (The two checks it runs, for reference / manual use:)

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

### Step 6: Report Staging PR URL (hand off — the user merges staging FIRST)

Do NOT create the production PR yet. The staging PR must be merged and its deploy verified
before the prod PR can exist (Step 7's gate) — creating it now is the double-review furnace
this ordering exists to prevent. Return the staging PR URL and stop here until the user
confirms the merge. The user will:
1. Review the PR diff
2. Merge it (regular merge, NOT squash — preserves commit history)
3. Staging auto-deploys after merge (~3–5 min)

**Do NOT attempt `gh pr merge` — this is blocked by hooks.**

### Step 7: Create Production PR (ONLY after the user confirms staging is merged + healthy)

This is the single prod-PR-creation step, and it runs AFTER Step 6's staging merge — never
before. If staging isn't merged yet, you are still in Step 6.

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

Only after all three pass, create the prod PR (or note if one already exists). Return the
production PR URL.

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

**Do NOT attempt to merge the production PR** — the user merges production PRs manually.

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

## Step 8: Worktree Cleanup (after staging PR created)

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

## Cross-Repo Shipping Mode

**Detection:** read `.claude/window-id` — if it starts with `x`, this is a cross-repo feature spanning Vouchers / Reservations / FM V3. **Read `reference/cross-repo.md` and follow it** for affected-repo detection, per-repo commit/push, cross-referenced PR creation in deploy order (Vouchers → Reservations → FM V3), and cross-repo cleanup. All core gates (Step 1a–4b, 5b) still run per repo. Single-repo ships ignore this section.

## More reference

- `reference/parity-gate.md` — the full Step 1b sweep checklist (Parts 1–3: cross-site parity, adversarial state/concurrency, edge/sub-case/trust-boundary). The spec the `parity-sweep` + `money-concurrency-reviewer` agents must cover, and the manual fallback if agents are unavailable.
- `reference/deploy-reference.md` — CI/CD pipeline stages, multi-repo deploy order, post-deploy health-check URLs, and error handling.
