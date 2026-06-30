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
- **After accepting a plan** — verify worktree status before editing code

## Three Tiers

| Tier | When | Branch Prefix | Worktree? | Window ID |
|------|------|---------------|-----------|-----------|
| **1: Cross-Repo** | Feature spans 2+ repos | `x1-`, `x2-` | Only if repo is occupied by another agent | `x1`, `x2` |
| **2: Single-Repo** | Feature touches 1 repo | `w1-`, `w2-`, `w3-` | Always | `w1`, `w2`, `w3` |
| **3: Solo** | Zero other agents active anywhere | `s-` | Never | `s` |

### Tier Detection

1. Ask or infer: "Which repos does this feature touch?"
2. Count active agents across ALL repos (scan `active-work.md` files)
3. Route:
   - 2+ repos → **Tier 1**
   - 1 repo + other agents active → **Tier 2**
   - 1 repo + zero agents active → offer **Tier 3**

### Tier 1: Cross-Repo
- Create feature branches with the **same slug** in all affected repos (`feature/x1-slug`)
- Create worktrees only in repos where another agent is already active
- Register in each repo's `active-work.md` with `cross-repo:` tag
- Set `window-id` to `x1`/`x2` in each repo or worktree

### Tier 3: Solo Mode
- No worktree needed — work directly in the main checkout
- Set `window-id` to `s` (bypasses `enforce-worktree.sh`)
- If a second agent starts later, it creates its own worktree

## Configuration

Read `platform.config.json` for project settings:
- `project.repoDir` — repo directory name (e.g., "my-project")
- `branches.staging` — staging branch name
- `branches.featurePrefix` — feature branch prefix (default: "feature/")
- `agents.maxWindows` — max concurrent agent windows (default: 3)

## Architecture

Each agent gets its own worktree directory:
```
<repoDir>/          # main repo (staging — setup only, NEVER code here)
<repoDir>-w1/       # agent window 1 worktree
<repoDir>-w2/       # agent window 2 worktree
<repoDir>-w3/       # agent window 3 worktree
```

Worktrees share the same `.git` internals but have independent working files. Conflicts only surface at PR merge time.

## Workflow — 4 Phases (0 + A–C, Self-Healing)

### Phase 0: Doctrine / Plan Gate (run BEFORE any setup or code — MANDATORY)

This is the **primary enforcement point** for the Operating Doctrine
(`~/.claude/CLAUDE.md` top + `/doctrine`). Code does not get written until this passes.
Run `/doctrine plan-gate` and produce explicit written answers — not "looks fine":

1. **Spec trace.** Restate in 1–2 lines exactly what the user asked for. Everything you're
   about to build must trace to that ask or to a recommendation he approved. Any part with
   no trace is a surprise feature — cut it or get approval first.
2. **Value-add recommendations (DO surface these).** Name any missing/adjacent capability
   that would add real value — as a RECOMMENDATION, one line each (what + why). Build none
   of it until the user says yes; then design it completely before coding.
   (recommend → approve → design → build)
3. **Customer-contact gate (HARD).** Does anything here send/alter/enable an outbound
   message to a customer/rider — SMS, email, push, in-app notice, auto-call? If yes, list
   each channel + trigger + template and confirm the user's written sign-off, or STOP and
   get it. **Never start unspecced customer-contact work.**
4. **Risk & length flag (loud + specific).** Name the real blast radius (systems, data,
   money, customers), the genuine effort, the top risks — then proceed. Risk/length is
   handled out loud, NOT by deferring or shrinking the task.
5. **No-defer check.** Are you about to backlog or "phase-2" any of the asked work?
   Default is build it now — park only with the user's explicit yes.

If any item can't be satisfied, **resolve it with the user before proceeding to Phase A.**

### Phase A: Ground Truth Assessment

**Do NOT trust state files.** Check the actual filesystem and git state first.

```bash
# 1. What worktrees actually exist?
git worktree list

# 2. What does the window-id file say? (may be stale)
cat .claude/window-id 2>/dev/null || echo "none"

# 3. What's registered in active-work.md?
cat .claude/active-work.md

# 4. What branch are we on?
git rev-parse --abbrev-ref HEAD

# 5. Are we in a worktree or the main repo?
git rev-parse --git-dir
# ".git" = main repo, contains "/worktrees/" = worktree
```

**For each possible worktree** (w1 through wN based on `agents.maxWindows`):

```bash
# Read repoDir from platform.config.json
REPO_DIR=$(grep -o '"repoDir"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json | head -1 | sed 's/.*"repoDir"[[:space:]]*:[[:space:]]*"//;s/"$//')
: "${REPO_DIR:=$(basename $(git rev-parse --show-toplevel))}"

# Does the directory actually exist on disk?
test -d "../${REPO_DIR}-wX" && echo "wX: EXISTS" || echo "wX: MISSING"

# Is its branch merged into staging already?
STAGING=$(grep -o '"staging"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json | head -1 | sed 's/.*"staging"[[:space:]]*:[[:space:]]*"//;s/"$//')
: "${STAGING:=staging}"
git merge-base --is-ancestor feature/wX-slug origin/$STAGING 2>/dev/null && echo "MERGED" || echo "ACTIVE"
```

**Report findings** to the user:
- "Found worktree w1 at ../<repoDir>-w1 — branch feature/w1-foo (active)"
- "Found orphaned registration for w2 — worktree directory missing"
- "Window-id file says w1 but no worktree exists — stale from previous session"

### Phase B: Cleanup Stale State

Based on Phase A findings, clean up anything orphaned. **Report every cleanup action to the user.**

```bash
# Read staging branch from config
STAGING=$(grep -o '"staging"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json | head -1 | sed 's/.*"staging"[[:space:]]*:[[:space:]]*"//;s/"$//')
: "${STAGING:=staging}"

# Prune worktrees that point to missing directories
git worktree prune

# If main repo is NOT on staging, switch to it
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "$STAGING" ]; then
  echo "Main repo on '$CURRENT_BRANCH', switching to $STAGING..."
  git stash push -m "letsbuild cleanup stash" 2>/dev/null
  git checkout "$STAGING"
fi

# Abort any in-progress merge or rebase
git merge --abort 2>/dev/null
git rebase --abort 2>/dev/null

# Pull latest staging
git fetch origin "$STAGING"
git pull origin "$STAGING"
```

**For each stale entry found:**

| Condition | Action |
|-----------|--------|
| Worktree listed in `git worktree list` but directory is gone | `git worktree prune` |
| active-work.md row exists but worktree directory is gone | Remove the row from active-work.md |
| Branch is merged into staging (ancestor check passes) | Remove worktree (`git worktree remove`), remove row, report "Previous work was merged" |
| window-id file has a real value (not `setup`) in main repo | Overwrite with `setup` |

**After cleanup, reset the main repo's window-id:**

```bash
echo "setup" > .claude/window-id
```

### Phase C: Atomic Assignment (All-or-Nothing)

Every step validates success. If ANY step fails, rollback everything done so far and report the error clearly.

**Step 1: Determine available window**

Check which windows are free based on Phase A/B results. Pick the lowest available number. If all windows are occupied, **STOP**: "All agent windows are occupied. Close one first or clean up a stale worktree."

**Step 2: Create feature branch**

```bash
WINDOW_ID="wX"  # assigned in step 1
SLUG="short-description"  # from user's task description, kebab-case
FEATURE_PREFIX=$(grep -o '"featurePrefix"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json | head -1 | sed 's/.*"featurePrefix"[[:space:]]*:[[:space:]]*"//;s/"$//')
: "${FEATURE_PREFIX:=feature/}"
BRANCH="${FEATURE_PREFIX}${WINDOW_ID}-${SLUG}"

git branch "$BRANCH" "$STAGING"

# VERIFY — if this fails, stop immediately
git rev-parse --verify "$BRANCH" || { echo "ERROR: Branch creation failed"; exit 1; }
```

**Step 3: Create worktree**

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_DIR=$(grep -o '"repoDir"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json | head -1 | sed 's/.*"repoDir"[[:space:]]*:[[:space:]]*"//;s/"$//')
: "${REPO_DIR:=$(basename $REPO_ROOT)}"
WORKTREE_PATH="${REPO_ROOT}/../${REPO_DIR}-${WINDOW_ID}"

git worktree add "$WORKTREE_PATH" "$BRANCH"

# VERIFY — if this fails, delete the branch and stop
if [ ! -d "$WORKTREE_PATH" ]; then
  echo "ERROR: Worktree creation failed"
  git branch -D "$BRANCH"
  exit 1
fi
```

**Step 4: Copy gitignored config to worktree**

```bash
mkdir -p "$WORKTREE_PATH/.claude"

# Copy window identity — write ONLY to worktree, main repo keeps "setup"
echo "$WINDOW_ID" > "$WORKTREE_PATH/.claude/window-id"
echo "setup" > .claude/window-id

# Copy env file — report if missing
if [ -f ".env" ]; then
  cp ".env" "$WORKTREE_PATH/.env"
  echo "Copied .env to worktree"
else
  echo "WARNING: No .env file found — worktree will not have environment variables"
fi

# Copy Claude settings
for f in settings.json settings.local.json; do
  if [ -f ".claude/$f" ]; then
    cp ".claude/$f" "$WORKTREE_PATH/.claude/$f"
    echo "Copied $f to worktree"
  fi
done

# Copy hooks directory
if [ -d ".claude/hooks" ]; then
  cp -r ".claude/hooks" "$WORKTREE_PATH/.claude/hooks"
  echo "Copied hooks to worktree"
fi
```

**Step 5: Register work**

```bash
DATE=$(date +%Y-%m-%d)
ROW="| $WINDOW_ID | $BRANCH | ../${REPO_DIR}-${WINDOW_ID} | <area description> | $DATE |"

# Add to main repo active-work.md
echo "$ROW" >> .claude/active-work.md

# Copy updated active-work.md to worktree
cp .claude/active-work.md "$WORKTREE_PATH/.claude/active-work.md"

# VERIFY registration
if ! grep -qF "$BRANCH" .claude/active-work.md; then
  echo "ERROR: Registration failed"
  git worktree remove "$WORKTREE_PATH" --force
  git branch -D "$BRANCH"
  exit 1
fi
```

**Step 6: Push branch to remote**

```bash
cd "$WORKTREE_PATH"
git push origin "$BRANCH" -u
```

**Step 7: Final verification and brief**

```
Ready to build!

Window: wX
Branch: feature/wX-<slug>
Worktree: ../<repoDir>-wX

IMPORTANT: Open a NEW Claude Code window pointed at the worktree path.
All coding work must happen in that directory, NOT in the main repo.
```

## Important Rules

- **NEVER skip this skill** — hooks block commits if your branch isn't registered
- **NEVER work in the main repo checkout** — `enforce-worktree.sh` blocks file edits there
- **NEVER use another agent's worktree** — each window has its own
- **Owner prefix branches are reserved for human work** — never use them
- **Main repo window-id is always `setup`** — real window IDs only exist in worktrees
- **Rollback on failure** — if any step in Phase C fails, undo all previous steps

## Error Recovery

| Error | Cause | Fix |
|-------|-------|-----|
| "Worktree already exists" | Stale from previous session | Phase B cleanup handles this automatically |
| "Branch already exists" | Old branch not cleaned up | Delete it (only if not pushed/merged) |
| "All windows occupied" | Max concurrent worktrees | Ask user which to reclaim |
| "Registration failed" | Write failed | Automatic rollback; check file permissions |
| Main repo not on staging | Left on feature branch | Phase B handles this |

## Cleanup (after /shipit or when done)

When your PR is merged:

```bash
# From the main repo:
cd <main-repo-path>
git worktree remove ../<repoDir>-wX
git branch -d feature/wX-slug
git push origin --delete feature/wX-slug
# Remove row from .claude/active-work.md
git worktree prune
```
