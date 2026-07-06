# shipit — Cross-Repo Shipping Mode

Loaded on demand by the `shipit` core skill when `.claude/window-id` starts with `x` (a
cross-repo feature spanning Vouchers / Reservations / FM V3). Single-repo ships never read this.
Everything from the core workflow still applies per repo (gates, reviews, changelog); this file
only adds the multi-repo orchestration: affected-repo detection, deploy-order PR creation, and
cleanup.

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
