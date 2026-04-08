---
name: token-audit
description: |
  Token audit — context efficiency monitor. Analyzes total token footprint
  loaded into Claude Code context. Identifies waste, duplication, and
  optimization opportunities.
---

# Token Audit — Context Efficiency Monitor

Measures and optimizes the token footprint of your Claude Code environment.

## When to Use

- Periodically to check context health
- When Claude seems to lose context or behave inconsistently
- When adding new skills, agents, or memory files
- When asked to "audit tokens", "check context", or "optimize context"

## Workflow

### Step 1: Measure Footprint

Estimate tokens for each component (rough: 1 token ≈ 4 characters):

```bash
# CLAUDE.md files
find . -name "CLAUDE.md" -exec wc -c {} + 2>/dev/null

# Memory index
MEMORY_DIR=$(find ~/.claude/projects/ -name "MEMORY.md" -path "*$(basename $(pwd))*" 2>/dev/null | head -1)
if [ -n "$MEMORY_DIR" ]; then
  wc -c "$MEMORY_DIR"
  wc -c "$(dirname "$MEMORY_DIR")"/*.md 2>/dev/null
fi

# Skills
find .claude/skills -name "SKILL.md" -exec wc -c {} + 2>/dev/null

# Agents
find .claude/agents -name "*.md" -exec wc -c {} + 2>/dev/null

# Settings
wc -c .claude/settings.json 2>/dev/null
```

### Step 2: Identify Issues

Check for:

#### Duplicate Content
- Same rules in CLAUDE.md AND skill files
- Same instructions in multiple skills
- Memory files that duplicate CLAUDE.md content

#### Stale Content
- Memory files referencing deleted features
- TODO items that are resolved
- Outdated URLs or file paths

#### Oversized Components
- Skills > 500 lines (consider splitting)
- CLAUDE.md > 300 lines (consider trimming)
- Memory index > 200 lines (will be truncated)

#### Security
- No plaintext secrets in any context file
- No API keys or tokens
- No sensitive URLs or credentials

### Step 3: Produce Report

```
## Token Audit Report

### Context Budget
| Component | Characters | Est. Tokens | % of Total |
|-----------|-----------|-------------|------------|
| CLAUDE.md | X | X | X% |
| Memory (index) | X | X | X% |
| Memory (files) | X | X | X% |
| Skills (X files) | X | X | X% |
| Agents (X files) | X | X | X% |
| Settings | X | X | X% |
| **Total** | **X** | **X** | **100%** |

### Health Score: X/10

### Issues Found
- [WASTE] Duplicate rule in CLAUDE.md and code-review skill
- [STALE] Memory file references deleted feature
- [OVERSIZED] plan-eng-review skill is 450 lines

### Recommendations
1. ...
2. ...

### Session Advice
- Fresh conversation recommended: [yes/no]
- Unnecessary context loaded: [list]
```
