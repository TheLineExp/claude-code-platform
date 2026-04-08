---
name: effort-optimizer
description: |
  Analyzes the current task and recommends the optimal effort level and model.
  Suggests /effort and /model changes to balance quality vs. cost vs. speed.
  Auto-invoked at the start of major tasks.
---

# Effort Optimizer

Recommends the right Claude Code effort level and model for the current task.

## When to Use

- At the start of a new task (auto-detect from task description)
- When the user asks to "optimize effort" or "adjust model"
- When switching between task types (planning → coding → docs)

## Task Classification → Effort Mapping

| Task Type | Effort | Model | Reasoning |
|-----------|--------|-------|-----------|
| **Architecture / system design** | high | opus | Needs deep reasoning, trade-off analysis |
| **Complex debugging** | high | opus | Needs full codebase understanding |
| **New feature implementation** | high | opus | Needs architecture awareness |
| **Plan review (eng/design/ceo)** | high | opus | Needs critical thinking |
| **Security review** | high | opus | Cannot miss vulnerabilities |
| **Simple bug fix** | medium | sonnet | Focused scope, known pattern |
| **Refactoring** | medium | sonnet | Mechanical transformation |
| **Test writing** | medium | sonnet | Follow existing patterns |
| **Documentation updates** | low | sonnet | Straightforward text work |
| **Changelog / release notes** | low | sonnet | Summarization task |
| **File exploration / research** | low | sonnet | Read-heavy, low generation |
| **Git operations (commit, PR)** | low | sonnet | Formulaic steps |
| **CSS / styling tweaks** | medium | sonnet | Visual precision needed |
| **Config file changes** | low | haiku | Simple edits |

## How to Apply

When starting a task, classify it and suggest the optimal settings:

```
Based on this task, I recommend:
  /effort [level] — [reason]
  /model [model] — [reason]

Want me to proceed with the current settings, or should we adjust?
```

### Hybrid Mode

For multi-phase work, recommend `opusplan`:
```
/model opusplan
```
This uses Opus for planning (deep reasoning) and auto-switches to Sonnet for execution (faster, cheaper). Ideal for the `/letsbuild → develop → /shipit` workflow.

## Cost Awareness

| Model | Input Cost | Output Cost | Speed |
|-------|-----------|-------------|-------|
| Opus 4.6 | $3/MTok | $15/MTok | Standard |
| Opus 4.6 (fast) | $30/MTok | $150/MTok | 2.5x faster |
| Sonnet 4.6 | $1/MTok | $5/MTok | Fast |
| Haiku 4.5 | $0.25/MTok | $1.25/MTok | Fastest |

### Rules

1. **Never use Opus for documentation-only tasks** — Sonnet is 3x cheaper and equally capable
2. **Never use Haiku for security reviews** — too critical for cost optimization
3. **Suggest `opusplan` for mixed sessions** — best of both worlds
4. **Warn about fast mode cost** — 10x input price; only recommend for time-critical work
5. **If the user has been in the same session for 50+ tool calls**, suggest Sonnet to conserve quota

## Integration with Session Tracker

When the session tracker reports high tool count (via stderr), factor that into recommendations:
- **50+ calls**: Suggest switching to Sonnet if on Opus (conserve remaining quota)
- **80+ calls**: Strongly suggest wrapping up or opening a new window
- **120+ calls**: Recommend new window regardless
