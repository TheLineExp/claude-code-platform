---
name: plan-eng-review
description: |
  Engineering plan review. Lock in the execution plan — architecture,
  data flow, edge cases, test coverage, performance. Walks through
  issues interactively with opinionated recommendations.
---

# Engineering Plan Review

Lock in the execution plan. Architecture, data flow, diagrams, edge cases, test coverage, performance.

## When to Use

- When asked to "review the architecture", "engineering review", or "lock in the plan"
- After a plan is written but before implementation begins
- When evaluating technical approach for a feature

## AskUserQuestion Format

**ALWAYS follow this structure:**
1. **Re-ground:** State the project, branch, and current task (1-2 sentences)
2. **Simplify:** Explain in plain English. No raw function names or jargon.
3. **Recommend:** `RECOMMENDATION: Choose [X] because [reason]`
4. **Options:** `A) ... B) ... C) ...`

## Completeness Principle

AI-assisted coding makes the marginal cost of completeness near-zero:
- If Option A is complete (all edge cases, full coverage) and Option B is a shortcut — **always recommend A**
- "Good enough" is the wrong instinct when "complete" costs minutes more
- Recommend boiling lakes (100% coverage for a module). Flag oceans (multi-quarter rewrites) as out of scope.

## Review Process — 4 Sections

### Section 1: Architecture Review

Read the plan file and all critical files. Evaluate:

- **Data flow**: Trace every request from entry point to response. Are there gaps?
- **Separation of concerns**: Is business logic in the right layer?
- **Dependencies**: New packages justified? Version conflicts?
- **Blast radius**: What else could break? Which systems are affected?
- **Scalability**: Will this approach handle 10x growth?

Present findings as a table:

| Dimension | Score (1-5) | Finding |
|-----------|-------------|---------|
| Data flow clarity | X | ... |
| Separation of concerns | X | ... |
| Dependency health | X | ... |
| Blast radius | X | ... |
| Scalability | X | ... |

### Section 2: Code Quality Forecast

Based on the plan, predict:
- Where will complexity concentrate?
- What patterns should be used?
- What's the testing strategy?
- What could become tech debt?

### Section 3: Test Coverage Plan

For every feature in the plan:
- [ ] Unit tests identified
- [ ] Integration tests identified
- [ ] Edge cases listed
- [ ] Error scenarios covered
- [ ] Performance implications noted

### Section 4: Performance & Failure Modes

- What happens when external services are down?
- What happens under load?
- What are the most likely failure modes?
- What monitoring/alerting is needed?

## Cognitive Patterns for Engineering Review

Apply these senior engineering instincts:

1. **Blast radius instinct** — "What else could this break?"
2. **Boring by default** — Prefer proven patterns over clever solutions
3. **Incremental over revolutionary** — Can this ship in smaller pieces?
4. **Test-first thinking** — "How would I test this?" reveals design issues
5. **Failure mode awareness** — What happens when things go wrong?
6. **Dependency skepticism** — Every dependency is a liability
7. **State management paranoia** — Where does state live? Who mutates it?

## Output

After completing all sections, produce:

```
## Engineering Review Summary

Overall Confidence: HIGH / MEDIUM / LOW

### Architecture: X/5
[key findings]

### Code Quality Forecast: X/5
[key findings]

### Test Coverage: X/5
[key findings]

### Performance & Reliability: X/5
[key findings]

### Recommended Changes Before Implementation
1. ...
2. ...

### Approved to Proceed: YES / YES_WITH_CHANGES / NO
```
