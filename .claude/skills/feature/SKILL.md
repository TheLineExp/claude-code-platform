---
name: feature
description: Manage feature requests. Add new ideas, review pending requests, or list all. Auto-invoked during planning to check alignment with roadmap.
user_invocable: true
---

# Feature Request Manager

Tracks and manages feature requests in `docs/FEATURE_REQUESTS.md`.

## Commands

- `/feature add <description>` — Add a new feature request
- `/feature review` — Review and prioritize pending requests
- `/feature list` — List all feature requests

## Feature Request Format

When adding a new request, create or append to `docs/FEATURE_REQUESTS.md`:

```markdown
## [ID] Feature Title

- **Status:** Pending / In Progress / Shipped / Declined
- **Priority:** P0 (Critical) / P1 (High) / P2 (Medium) / P3 (Low)
- **Requested:** YYYY-MM-DD
- **Description:** What the feature does and why it's needed
- **Notes:** Implementation considerations, dependencies, alternatives
```

## Review Process

When reviewing (`/feature review`):

1. Read `docs/FEATURE_REQUESTS.md`
2. Read project roadmap if it exists (check `docs/` for planning docs)
3. For each pending request, assess:
   - Alignment with project goals
   - Technical complexity
   - Dependencies on other work
   - User impact
4. Recommend priority and next steps

## Auto-Review During Planning

When entering plan mode for a new feature, check `docs/FEATURE_REQUESTS.md` to see if any existing requests overlap with or inform the current work.
