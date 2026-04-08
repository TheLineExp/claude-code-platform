---
name: document-release
description: |
  Post-ship documentation update. Reads all project docs, cross-references
  the diff, updates README/ARCHITECTURE/CONTRIBUTING/CLAUDE.md to match
  what shipped. Polishes CHANGELOG voice, cleans up TODOS.
---

# Document Release

Post-ship documentation sync. Ensures docs match what actually shipped.

## When to Use

- After merging a significant feature or release
- When asked to "update docs", "sync documentation", or "document release"
- After `/shipit` completes successfully

## Workflow

### Step 1: Pre-Flight — Gather Diff

```bash
# What changed since last release/tag?
git log --oneline HEAD~20..HEAD
git diff --stat HEAD~20..HEAD
```

### Step 2: Audit Each Doc File

For each documentation file in the project:

#### README.md
- [ ] Features list matches current capabilities
- [ ] Setup instructions still accurate
- [ ] Environment variables documented
- [ ] Examples work with current API

#### ARCHITECTURE.md (if exists)
- [ ] System diagram reflects current structure
- [ ] Data flow descriptions accurate
- [ ] New components/services documented
- [ ] Removed components cleaned up

#### CONTRIBUTING.md (if exists)
- [ ] Development setup steps current
- [ ] Branch strategy documented
- [ ] Testing instructions work
- [ ] PR process documented

#### CLAUDE.md
- [ ] Project rules still accurate
- [ ] File structure section current
- [ ] Environment variables documented
- [ ] Critical rules haven't changed incorrectly

### Step 3: CHANGELOG Polish

If a CHANGELOG exists:
- Ensure new entries exist for shipped features
- Polish voice: consistent tense, clear descriptions
- **Never clobber existing entries** — only add or refine
- Group by: Added, Changed, Fixed, Removed

### Step 4: TODO Cleanup

Search for TODOs in the codebase:

```bash
grep -rn "TODO\|FIXME\|HACK\|XXX" --include="*.js" --include="*.ts" --include="*.py" --include="*.rb" | head -30
```

For each TODO:
- If resolved by recent work → remove
- If still valid → leave
- If deferred → document in backlog

### Step 5: Cross-Doc Consistency

Verify that information is consistent across all docs:
- Version numbers match
- Feature descriptions align
- URLs and endpoints are current
- Team/contact info is up to date

## Output

```
## Documentation Update Summary

### Files Updated
- README.md: [changes made]
- CLAUDE.md: [changes made]
- ...

### TODOs Resolved: X
### TODOs Remaining: X
### Consistency Issues Fixed: X

### Recommendation
[All docs current / X files need manual review]
```

## Rules

- **Auto-update factual corrections** (wrong file paths, outdated env vars, etc.)
- **Ask before risky/subjective changes** (rewording descriptions, reorganizing sections)
- **Never delete content without confirmation** — suggest removals, don't execute
- **Preserve all CHANGELOG entries** — only add, never remove
