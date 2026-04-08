---
name: retro
description: |
  Weekly engineering retrospective. Analyzes commit history, work patterns,
  and code quality metrics with persistent history and trend tracking.
  Team-aware: breaks down per-person contributions with praise and growth areas.
---

# Weekly Engineering Retrospective

Analyzes git history, work patterns, and code quality to produce actionable retrospectives.

## When to Use

- Weekly team retrospectives
- When asked "what did we ship", "weekly retro", or "engineering retrospective"
- Sprint reviews and planning sessions

## Parameters

- `/retro` — default: last 7 days
- `/retro 14d` — custom window (e.g., 14 days, 30d, etc.)

## Workflow

### Step 1: Gather Data

```bash
# Set time window (default 7 days)
SINCE="7 days ago"

# Commit history
git log --since="$SINCE" --oneline --all

# Per-author breakdown
git shortlog --since="$SINCE" --all -sn

# Files changed
git log --since="$SINCE" --all --name-only --pretty=format: | sort | uniq -c | sort -rn | head -20

# LOC changes
git log --since="$SINCE" --all --stat --pretty=format: | tail -1
```

### Step 2: Analyze Patterns

#### Commit Types
Categorize commits by prefix: feat, fix, refactor, style, docs, chore, test

#### Work Sessions
Detect sessions using 45-minute gap threshold between commits. Classify:
- **Deep work**: >2 hours continuous
- **Medium session**: 30min-2hr
- **Micro session**: <30min

#### Hotspot Analysis
Which files were changed most frequently? These are your complexity hotspots.

#### PR Flow
```bash
# Merged PRs
gh pr list --state merged --search "merged:>$(date -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)" --limit 20

# Open PRs
gh pr list --state open --limit 10
```

### Step 3: Per-Person Analysis

For each contributor:
- Commits, LOC added/removed
- Primary areas of work
- **Praise**: What they shipped well
- **Growth**: Patterns to improve (constructive, specific)

### Step 4: Metrics Dashboard

```
## Retro: [date range]

### Ship Summary
- Commits: X
- Contributors: X
- PRs merged: X
- LOC: +X / -X (net: X)

### Commit Types
feat: X | fix: X | refactor: X | test: X | chore: X | docs: X

### Work Patterns
Deep sessions: X | Medium: X | Micro: X
Focus score: X/10 (higher = more deep work)

### Ship of the Week
[most impactful PR or feature]

### Hotspots (most-changed files)
1. path/to/file (X changes)
2. ...

### Per-Person
| Author | Commits | LOC | Primary Area | Highlight |
|--------|---------|-----|-------------|-----------|
| ... | ... | ... | ... | ... |

### Trends vs. Last Retro
[compare metrics if previous retro data exists]

### Action Items
1. ...
2. ...
```

### Step 5: Persist Snapshot

Save retro data for trend tracking:

```bash
mkdir -p .context/retros
# Save JSON snapshot with date, metrics, and highlights
```
