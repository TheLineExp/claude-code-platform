---
name: feature
description: Manage LARGE, undefined feature projects — net-new capabilities or product redesigns that need scoping/design before they can be built. Add ideas, review pending requests, or list all. Auto-invoked during planning to check alignment with roadmap. Distinct from /todo (small, well-defined quality-sweep fixes/tweaks/ops).
user_invocable: true
---

# Feature Request Manager

Tracks and manages large/undefined feature projects in `docs/FEATURE_REQUESTS.md`.

## Scope boundary — `/feature` vs `/todo`

This is the line that keeps the two backlogs from overlapping (the axis is
**scope/definition, NOT fix-vs-feature**):

- **`/feature` (here) = LARGE + undefined.** A net-new capability or a redesign
  that needs a scoping/design pass before anyone can build it (typically
  multi-PR). If it needs design, it's a feature.
- **`/todo` = SMALL + already defined.** A fix, a tweak, a one-line change, a
  contained UI affordance, an ops/cleanup chore a dev could pick up as-is —
  groupable into a quality sweep.

If an idea is small and obvious enough to "just do," it belongs in `/todo` — say
so and offer `/todo add` instead of filing an FR. If a `/todo` item turns out to
need a design pass, promote it here.

If the project spans more than one repo/package, tag each request with its
**Repo(s)/area** so the backlog stays scannable.

## Commands

- `/feature add <description>` — Add a new feature project (after a size check)
- `/feature review` — Review and prioritize pending requests
- `/feature list` — List all feature requests

## Feature Request Format

`/feature add` — **size check first:** if the description is a small,
already-defined fix / tweak / one-line change / contained UI affordance / ops
chore, it is NOT a feature — it belongs in `/todo`. Say so and offer
`/todo add` instead. Only for genuinely large/undefined work, create or append
to `docs/FEATURE_REQUESTS.md`:

```markdown
## [ID] Feature Title

- **Status:** Pending / In Progress / Shipped / Declined
- **Priority:** P0 (Critical) / P1 (High) / P2 (Medium) / P3 (Low)
- **Repo(s)/area:** which repo(s) or area this spans (if multi-repo)
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
   - **Right backlog?** If a request has shrunk to a small, defined task, move it
     to `/todo`; flag any that should be promoted from `/todo` up to here.
4. Recommend priority and next steps

## Auto-Review During Planning

When entering plan mode for a new feature, check `docs/FEATURE_REQUESTS.md` to see if any existing requests overlap with or inform the current work.
