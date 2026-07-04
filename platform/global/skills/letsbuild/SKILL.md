---
name: letsbuild
description: Safe feature start workflow with multi-agent coordination. Creates an isolated git worktree, assigns window ID, creates feature branch, and registers work. MANDATORY before starting any work. Prevents agents from overwriting each other. Self-healing — cleans up stale state from previous sessions automatically.
---

# Let's Build — Multi-Agent Safe Start (3-Tier)

This skill is **MANDATORY** before starting any coding work. It sets up isolated workspaces so agents cannot overwrite each other's files.

## When to Use

- **ALWAYS** at the start of a new task or feature
- When the user says "let's build", "start working on", or describes a feature to implement
- Before making ANY code changes
- **After accepting a plan** — verify workspace status before editing code

## Three Tiers

| Tier | When | Branch Prefix | Worktree? | Window ID |
|------|------|---------------|-----------|-----------|
| **1: Cross-Repo** | Feature spans 2-3 repos | `x1-`, `x2-` | Only if repo is occupied by another agent | `x1`, `x2` |
| **2: Single-Repo** | Feature touches 1 repo | `w1-`, `w2-`, `w3-` | Always | `w1`, `w2`, `w3` |
| **3: Solo** | Zero other agents active anywhere | `s-` | Never | `s` |

## Repo Map

| Repo | Path | GitHub | Prod Branch |
|------|------|--------|-------------|
| Reservations | `/Users/mikekunz/Documents/Volo Technologies/fleetmanager-reservations` | `TheLineExp/fleetmanager-reservations` | `master` |
| FM V3 | `/Users/mikekunz/Documents/Volo Technologies/Fleetmanager_V3` | `TheLineExp/Fleetmanager_V3` | `main` |
| Vouchers | `/Users/mikekunz/Documents/Volo Technologies/fleetmanager-vouchers` | `TheLineExp/fleetmanager-vouchers` | `master` |

---

## Workflow — 5 Phases (0 + A–D)

### Phase 0: Doctrine / Plan Gate (run BEFORE any setup or code — MANDATORY)

This is the **primary enforcement point** for the Operating Doctrine
(`~/.claude/CLAUDE.md` top + `/doctrine`). Code does not get written until this passes.
Run `/doctrine plan-gate` and produce explicit written answers — not "looks fine":

1. **Spec trace.** Restate in 1–2 lines exactly what Mike asked for. Everything you're
   about to build must trace to that ask or to a recommendation he approved. Any part with
   no trace is a surprise feature — cut it or get approval first.
2. **Value-add recommendations (DO surface these).** Name any missing/adjacent capability
   that would add real value — as a RECOMMENDATION, one line each (what + why). Build none
   of it until Mike says yes; then design it completely before coding.
   (recommend → approve → design → build)
3. **Customer-contact gate (HARD).** Does anything here send/alter/enable an outbound
   message to a customer/rider — SMS, email, push, in-app notice, auto-call? If yes, list
   each channel + trigger + template and confirm Mike's written sign-off, or STOP and get
   it. **Never start unspecced customer-contact work.**
4. **Risk & length flag (loud + specific).** Name the real blast radius (systems, data,
   money, customers), the genuine effort, the top risks — then proceed. Risk/length is
   handled out loud, NOT by deferring or shrinking the task.
5. **No-defer check.** Are you about to backlog or "phase-2" any of the asked work?
   Default is build it now — park only with Mike's explicit yes.

If any item can't be satisfied, **resolve it with Mike before proceeding to Phase A.**

### Phase A: Ground Truth Assessment (ALL repos)

**Do NOT trust state files.** Check the actual filesystem and git state first.

**For each of the three repos**, run:

```bash
cd <REPO_PATH>

# 1. What worktrees actually exist?
git worktree list

# 2. What does the window-id file say?
cat .claude/window-id 2>/dev/null || echo "none"

# 3. What's registered in active-work.md?
cat .claude/active-work.md 2>/dev/null || echo "no active-work.md"

# 4. What branch are we on?
git rev-parse --abbrev-ref HEAD

# 5. Are we in a worktree or the main repo?
git rev-parse --git-dir
```

**Check existing worktrees** (for repos that use them — Reservations, Vouchers):

```bash
# Does the directory actually exist on disk?
for W in w1 w2 w3 x1 x2; do
  test -d "../<repo-name>-$W" && echo "$W: EXISTS" || echo "$W: MISSING"
done
```

**Report findings** to the user across all repos:
- "Reservations: w1 active (feature/w1-refund-system), w2 active (feature/w2-timezone-fixes)"
- "FM V3: w3 active (feature/w3-reservations-refund-ui)"
- "Vouchers: w1 active, w2 active"

### Phase B: Determine Tier

Based on Phase A findings and the user's task description:

**Step 1: Ask the user (or infer from description):**
- "Which repos does this feature touch?"
- Options: Reservations only, FM V3 only, Vouchers only, Reservations + FM V3, Reservations + Vouchers, All three, etc.

**Step 2: Count active agents across ALL repos:**
- Parse all `active-work.md` files from Phase A
- If ZERO agents active anywhere AND feature is single-repo → offer **Tier 3 (Solo)**
- If feature spans 2+ repos → **Tier 1 (Cross-Repo)**
- If feature is single-repo AND other agents are active → **Tier 2 (Single-Repo)**

**Report the tier selection:**
- "This is a cross-repo feature (Reservations + Vouchers). Using Tier 1."
- "Single-repo feature, other agents active. Using Tier 2 (worktree)."
- "No other agents active. Using Tier 3 (solo mode — no worktree needed)."

### Phase C: Cleanup Stale State

Based on Phase A findings, clean up anything orphaned. **Report every cleanup action.**

**For each affected repo:**

```bash
cd <REPO_PATH>

# Prune worktrees that point to missing directories
git worktree prune

# If main repo is NOT on staging, switch to it (only if no active agent is using it)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "staging" ]; then
  echo "Repo on '$CURRENT_BRANCH', switching to staging..."
  git stash push -m "letsbuild cleanup stash" 2>/dev/null
  git checkout staging
fi

# Abort any in-progress merge or rebase
git merge --abort 2>/dev/null
git rebase --abort 2>/dev/null

# Pull latest staging
git fetch origin staging
git pull origin staging
```

**Stale entry cleanup rules:**

| Condition | Action |
|-----------|--------|
| Worktree listed but directory is gone | `git worktree prune` |
| active-work.md row but worktree is gone | Remove the row |
| Branch is merged into staging | Remove worktree, remove row, report "Previous work was merged" |
| window-id has a real value (not `setup`) in main repo AND no active agent owns it | Overwrite with `setup` |

**Worktree GC (MANDATORY every letsbuild — keeps the fleet under control):** enumerate ALL
worktrees, not just w1–w3 (stale `xN`, `rel*`, `bm*` etc. accumulate — 100+ were once found
on disk). For each worktree beyond the main checkout whose branch is merged into
origin/staging and whose tree is clean, remove it:

```bash
git fetch origin staging
git worktree list --porcelain | awk '/^worktree /{print $2}' | tail -n +2 | while read -r WT; do
  WTBRANCH=$(git -C "$WT" branch --show-current)
  # skip worktrees registered to an ACTIVE agent in active-work.md
  grep -q "$(basename "$WT")" .claude/active-work.md 2>/dev/null && continue
  if [ -n "$WTBRANCH" ] && git merge-base --is-ancestor "$WTBRANCH" origin/staging 2>/dev/null; then
    git worktree remove "$WT" && echo "GC'd merged worktree: $WT"
  fi
done
git worktree prune
```

`git worktree remove` refuses dirty trees — that refusal is the safety. Report (don't force)
any dirty leftovers so Mike can decide.

**CAUTION:** Do NOT reset a window-id that belongs to an active agent (check active-work.md first).

### Phase D: Setup (tier-specific)

---

## Tier 1: Cross-Repo Setup

**Prefix assignment:** Find the lowest available cross-repo ID (`x1`, `x2`, `x3`).

```bash
# Check which x-IDs are in use across all repos
for REPO in fleetmanager-reservations fleetmanager-vouchers Fleetmanager_V3; do
  grep "^| x" "/Users/mikekunz/Documents/Volo Technologies/$REPO/.claude/active-work.md" 2>/dev/null
done
```

Pick the lowest unused `x1`/`x2`/`x3`.

**For each affected repo**, decide isolation strategy:

```
IF another agent is active in this repo (has a row in active-work.md with an existing worktree):
  → Create a WORKTREE for this repo
ELSE:
  → Work directly in the main checkout on a feature branch
```

**Step 1: Create feature branches (same slug in all repos)**

```bash
XREF="x1"  # assigned above
SLUG="feature-name"  # from user's task, kebab-case
BRANCH="feature/${XREF}-${SLUG}"

for REPO_PATH in <list of affected repo paths>; do
  cd "$REPO_PATH"
  git fetch origin staging
  git branch "$BRANCH" origin/staging
  git rev-parse --verify "$BRANCH" || { echo "ERROR: Branch creation failed in $REPO_PATH"; exit 1; }
done
```

**Step 2: Create worktrees where needed**

Only for repos where another agent is active:

```bash
cd <REPO_PATH>
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
WORKTREE_PATH="$(git rev-parse --show-toplevel)/../${REPO_NAME}-${XREF}"

git worktree add "$WORKTREE_PATH" "$BRANCH"

# Copy config to worktree. Guard hooks are GLOBAL now (~/.claude/hooks fires in every
# session, worktrees included) — do NOT copy .claude/hooks or the hooks-only
# .claude/settings.json into the worktree (that copy caused the old .claude/hooks/hooks
# "Z1" nesting bug and re-introduced per-repo drift). Only per-worktree state + local env.
mkdir -p "$WORKTREE_PATH/.claude"
echo "$XREF" > "$WORKTREE_PATH/.claude/window-id"
[ -f ".env" ] && cp ".env" "$WORKTREE_PATH/.env"
[ -f ".claude/settings.local.json" ] && cp ".claude/settings.local.json" "$WORKTREE_PATH/.claude/settings.local.json"
```

**Step 3: Set window-id in repos used directly (no worktree)**

For repos where no worktree was created (working in main checkout):

```bash
cd <REPO_PATH>
echo "$XREF" > .claude/window-id
git checkout "$BRANCH"
```

**Step 4: Register in ALL affected repos**

```bash
DATE=$(date +%Y-%m-%d)
for REPO_PATH in <list of affected repo paths>; do
  WORK_DIR="<worktree path or '(main checkout)'>"
  ROW="| $XREF | $BRANCH | $WORK_DIR | cross-repo: <description> | $DATE |"
  echo "$ROW" >> "$REPO_PATH/.claude/active-work.md"

  # If worktree was created, copy active-work.md there too
  if [ -d "$WORKTREE_PATH" ]; then
    cp "$REPO_PATH/.claude/active-work.md" "$WORKTREE_PATH/.claude/active-work.md"
  fi
done
```

**Step 5: Push all branches**

```bash
for REPO_PATH in <list of working dirs — worktree or main checkout>; do
  cd "$REPO_PATH"
  git push origin "$BRANCH" -u
done
```

**Step 6: Generate workspace file (if worktrees were created)**

If any repos needed worktrees, generate a temporary workspace file:

```bash
cat > "/Users/mikekunz/Documents/Volo Technologies/cross-repo-${XREF}.code-workspace" << 'WORKSPACE'
{
  "folders": [
    {"path": "<reservations worktree or main repo>"},
    {"path": "<fm-v3 worktree or main repo>"},
    {"path": "<vouchers worktree or main repo>"}
  ]
}
WORKSPACE
```

If NO worktrees were needed (all repos available), use the existing `fleetmanager-reservations.code-workspace`.

**Step 7: Brief the agent**

```
Ready to build! (Cross-Repo Mode)

ID: x1
Branch: feature/x1-<slug> (same in all repos)
Repos:
  - Reservations: <path> (main checkout / worktree at ...)
  - FM V3: <path> (main checkout / worktree at ...)
  - Vouchers: <path> (main checkout / worktree at ...)

Other agents active:
  - (list from all active-work.md files)

Workspace: <path to workspace file>

IMPORTANT: When committing, cd to each repo's working directory first.
Each repo gets its own commits on its own feature branch.
```

---

## Tier 2: Single-Repo Setup (existing workflow)

Exactly the existing worktree-based workflow. For reference:

**Step 1: Determine available window**

Check `w1`, `w2`, `w3` — pick the lowest available (no active worktree at that path).

**Step 2: Create feature branch**

```bash
WINDOW_ID="wX"
SLUG="short-description"
BRANCH="feature/${WINDOW_ID}-${SLUG}"
git branch "$BRANCH" staging
```

**Step 3: Create worktree**

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
WORKTREE_PATH="${REPO_ROOT}/../${REPO_NAME}-${WINDOW_ID}"
git worktree add "$WORKTREE_PATH" "$BRANCH"
```

**Step 4: Copy config to worktree**

```bash
mkdir -p "$WORKTREE_PATH/.claude"
echo "$WINDOW_ID" > "$WORKTREE_PATH/.claude/window-id"
echo "setup" > .claude/window-id
[ -f ".env" ] && cp ".env" "$WORKTREE_PATH/.env"
[ -f ".claude/settings.local.json" ] && cp ".claude/settings.local.json" "$WORKTREE_PATH/.claude/settings.local.json"
# Guard hooks are GLOBAL (~/.claude/hooks fires in worktrees too) — do NOT copy
# .claude/hooks or the hooks-only .claude/settings.json into the worktree. That copy
# caused the old .claude/hooks/hooks "Z1" nesting bug and re-introduced per-repo drift.
```

**Step 5: Register work**

```bash
DATE=$(date +%Y-%m-%d)
ROW="| $WINDOW_ID | $BRANCH | ../${REPO_NAME}-${WINDOW_ID} | <area description> | $DATE |"
echo "$ROW" >> .claude/active-work.md
cp .claude/active-work.md "$WORKTREE_PATH/.claude/active-work.md"
```

**Step 6: Push and verify**

```bash
cd "$WORKTREE_PATH"
git push origin "$BRANCH" -u
```

**Step 7: Brief the agent**

```
Ready to build!

Window: wX
Branch: feature/wX-<slug>
Worktree: ../<repo-name>-wX

Other agents active:
  - (list from active-work.md)

IMPORTANT: Open a NEW Claude Code window pointed at:
  /Users/mikekunz/Documents/Volo Technologies/<repo-name>-wX

All coding work must happen in that directory, NOT in the main repo.
```

---

## Tier 3: Solo Mode Setup

No worktrees needed. Work directly in the main checkout.

**Step 1: Verify zero agents active**

Check ALL repos' `active-work.md` files. If ANY have active (non-stale) entries → fall back to Tier 1 or 2.

**Step 2: Create feature branch**

```bash
BRANCH="feature/s-${SLUG}"
git checkout -b "$BRANCH" staging
```

**Step 3: Set window-id**

```bash
echo "s" > .claude/window-id
```

**Step 4: Register**

```bash
DATE=$(date +%Y-%m-%d)
ROW="| s | $BRANCH | (main checkout) | <description> | $DATE |"
echo "$ROW" >> .claude/active-work.md
```

**Step 5: Push**

```bash
git push origin "$BRANCH" -u
```

**Step 6: Brief the agent**

```
Ready to build! (Solo Mode — no worktree needed)

Branch: feature/s-<slug>
Working in: main checkout (no other agents active)

Start coding right here — no need to open a new window.
The enforce-worktree.sh hook is bypassed in solo mode.
```

---

## Important Rules

- **Quote every path** — the repos live under `"Volo Technologies"` (contains a space).
  Unquoted paths caused 200+ failed commands in two weeks. Prefer the `~/vt` symlink
  (`~/vt/fleetmanager-reservations` etc.) in commands.
- **Subagents do NOT inherit your worktree cwd.** Every Agent/subagent prompt MUST begin
  with the absolute worktree path ("Work in <absolute-worktree-path>; use absolute paths in
  every command") — subagent path confusion caused 145 failed tool calls in two weeks.
- **NEVER skip this skill** — hooks block commits if your branch isn't registered
- **NEVER work in the main repo checkout without solo mode or cross-repo mode** — `enforce-worktree.sh` blocks file edits there
- **NEVER use another agent's worktree** — each window has its own
- **The `mk-` prefix is reserved for Michael's manual work** — never use it
- **Main repo window-id is `setup` when no agent is using it directly** — real window IDs exist in worktrees or during solo/cross-repo mode
- **NO `2>/dev/null` on critical operations** — all errors must be visible and reported
- **Rollback on failure** — if any step fails, undo all previous steps before stopping
- **Cross-repo branches use the SAME slug in ALL repos** — e.g., `feature/x1-refund-system` everywhere

## Error Recovery

| Error | Cause | Fix |
|-------|-------|-----|
| "Worktree already exists" | Stale from previous session | Phase C cleanup handles this |
| "Branch already exists" | Old branch not cleaned up | Delete it: `git branch -D feature/wX-old-slug` (only if not pushed/merged) |
| "All windows occupied" | Three active worktrees | Ask user which to reclaim, run cleanup |
| "Registration failed" | Write to active-work.md failed | Automatic rollback; check file permissions |
| "No .env file" | Env never created | Create `.env` from `.env.example` |
| Main repo not on staging | Left on feature branch by previous session | Phase C handles this (stash + checkout staging) |
| Merge conflict in main repo | Previous session left conflicts | Phase C aborts the merge/rebase |

## Docker Considerations

Worktrees share the git database but NOT the Docker environment. For running tests:

```bash
# Option 1: Run from main repo (preferred)
cd /Users/mikekunz/Documents/Volo Technologies/fleetmanager-reservations
docker-compose exec backend npm test

# Option 2: Point to main repo's compose file
COMPOSE_FILE=/Users/mikekunz/Documents/Volo Technologies/fleetmanager-reservations/docker-compose.yml docker-compose exec backend npm test
```

The backend container mounts the main repo's `backend/` directory — changes in worktrees won't be visible to Docker unless you update the volume mount.

## Cleanup (after /shipit or when done)

### Tier 2 Cleanup (single-repo worktree)

```bash
# From the main repo:
cd /Users/mikekunz/Documents/Volo Technologies/<repo-name>

git worktree remove ../<repo-name>-wX
git branch -d feature/wX-slug
git push origin --delete feature/wX-slug
# Remove row from .claude/active-work.md
git worktree prune
```

### Tier 1 Cleanup (cross-repo)

For EACH repo that was part of the cross-repo feature:

```bash
cd <REPO_PATH>

# Remove worktree if one was created
git worktree remove ../<repo-name>-xN 2>/dev/null
git worktree prune

# Delete the branch
git branch -d feature/xN-slug
git push origin --delete feature/xN-slug

# Remove row from active-work.md
# Reset window-id to setup (if it was set to xN)
WID=$(cat .claude/window-id 2>/dev/null)
if [[ "$WID" == x* ]]; then
  echo "setup" > .claude/window-id
fi
```

### Tier 3 Cleanup (solo)

```bash
# Just clean up the branch and registration
git checkout staging
git branch -d feature/s-slug
git push origin --delete feature/s-slug
# Remove row from active-work.md
echo "setup" > .claude/window-id
```

The `/shipit` skill handles cleanup automatically after PR creation.
