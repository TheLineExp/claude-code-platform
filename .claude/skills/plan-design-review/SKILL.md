---
name: plan-design-review
description: |
  Designer's eye plan review. Rates each design dimension 0-10,
  explains what would make it a 10, then fixes the plan to get there.
  For live site visual audits, use /design-review.
---

# Design Plan Review

Interactive design review for implementation plans. Evaluates UX, information architecture, visual hierarchy, and user journey completeness.

## When to Use

- When reviewing a plan that includes UI/UX changes
- When asked for "design review", "UX review", or "design feedback"
- Before implementing any user-facing feature

## AskUserQuestion Format

1. **Re-ground:** State the project, branch, and current task
2. **Simplify:** Explain in plain English, no jargon
3. **Recommend:** `RECOMMENDATION: Choose [X] because [reason]`
4. **Options:** `A) ... B) ... C) ...`

## Review Process — 7 Passes

### Pass 1: Information Architecture
- Does the navigation structure make sense?
- Can users find what they need in 3 clicks or less?
- Is related information grouped logically?

### Pass 2: States & Transitions
- Loading states defined?
- Empty states handled gracefully?
- Error states informative and actionable?
- Success states provide clear feedback?

### Pass 3: User Journey
- Happy path smooth and obvious?
- Edge cases handled (first-time user, power user, error recovery)?
- Progressive disclosure used appropriately?

### Pass 4: AI Slop Detection
- Any generic placeholder text?
- Icons that don't match their function?
- Layout patterns that don't serve the content?

### Pass 5: Design System Compliance
- Using existing components where possible?
- Design tokens (colors, spacing, typography) used consistently?
- No hardcoded values that should be tokens?

### Pass 6: Responsive Design
- Mobile-first approach?
- Touch targets >= 44px?
- Content readable at all breakpoints?
- No horizontal scroll on mobile?

### Pass 7: Key Decisions
- What design decisions need user input?
- What trade-offs exist between approaches?
- What's the minimum viable design vs. ideal?

## Design Cognitive Patterns

1. **Seeing the system** — Every screen is part of a whole
2. **Empathy as simulation** — Walk through as the actual user
3. **Hierarchy as service** — The most important thing should be most visible
4. **Constraint worship** — Constraints produce better design than freedom
5. **Progressive disclosure** — Show only what's needed now

## Output

Rate each dimension and produce:

```
## Design Review

| Dimension | Score | What Would Make It 10 |
|-----------|-------|-----------------------|
| Information Architecture | X/10 | ... |
| States & Transitions | X/10 | ... |
| User Journey | X/10 | ... |
| Design System Compliance | X/10 | ... |
| Responsive Design | X/10 | ... |
| Accessibility | X/10 | ... |

### Design Completeness Score: X/10

### Recommended Changes
1. ...
2. ...

### Questions for User
1. ...
```
