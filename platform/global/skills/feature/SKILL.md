---
name: feature
description: Unified, cross-repo backlog of LARGE, undefined feature projects across ALL FleetManager repos (reservations / FM V3 / vouchers / azure-ops) — net-new capabilities or product redesigns that need scoping/design before they can be built (typically multi-PR). Persistent + file-backed + cross-repo + cross-machine. Invoke with /feature to list; "/feature add ...", "/feature review", "/feature <filter>" to manage it. Use whenever the user says /feature, "feature requests", "the roadmap backlog", "add a feature idea", or wants to park/recall a large project. Auto-invoked during planning to check alignment. Distinct from /todo (small, well-defined quality-sweep fixes/tweaks/ops) and a repo's MASTER_PLAN.md (phase/planning tracking).
user_invocable: true
---

# /feature — unified cross-repo feature backlog

A single persistent, cross-repo, cross-machine list of **large, undefined
feature projects** across all FleetManager repos — net-new capabilities or
redesigns that need a scoping/design pass before anyone can build them
(typically multi-PR). It is the front door for "big idea, not yet scoped."

**Scope boundary (the line that separates `/feature` from `/todo`** — the axis is
**scope/definition, NOT fix-vs-feature):**
- `/feature` (here) = **LARGE + undefined.** A net-new capability or a redesign
  that needs a scoping/design pass before anyone can build it. If it needs
  design, it's a feature.
- `/todo` = **SMALL + already defined.** A fix, a tweak, a one-line change, a
  contained UI affordance, an ops/cleanup chore a dev could pick up as-is —
  groupable into a quality sweep.

If an idea is small and obvious enough to "just do," it belongs in `/todo` — say
so and offer `/todo add` instead of filing an FR. If a `/todo` item turns out to
need a design pass, promote it here.

## Backing file (single source of truth)

The list lives in the **git-synced** unified backlog so it spans every dev
machine. Resolve the location at runtime:

1. Read `~/.claude/backlog-location` — a one-line file written by
   `setup-machine.sh` holding the absolute path to the backlog dir on THIS
   machine (the `backlog/` dir inside the `claude-code-platform` repo clone).
2. The feature list is `<backlog-dir>/FEATURES.md`.
3. **Fallback** if `~/.claude/backlog-location` is missing: look for a
   `claude-code-platform/backlog/FEATURES.md` under the dirs listed in
   `~/.claude/settings.json` `additionalDirectories`. If still not found, tell
   the user to run `bash setup-machine.sh`; don't silently create a local-only file.

**Cross-machine sync (do this every time):**
- **Before reading:** `git -C <backlog-dir> pull --ff-only`. If it fails
  (offline / conflict), warn and proceed with the local copy — never block.
- **After writing:** `git -C <backlog-dir> add FEATURES.md && git -C <backlog-dir> commit -m "feature: <what changed>" && git -C <backlog-dir> push`.
  The platform repo's `main` is unprotected and these are data-only edits, so a
  direct push is correct — do NOT open a PR for routine backlog edits.

## Item format

Every request is a section, **always carrying a `Repo(s)/area` tag** so the
cross-repo list stays scannable:

```markdown
### FR-NNN: Feature Title
- **Repo(s)/area**: reservations | FM V3 | vouchers | azure | cross-repo | <area>
- **Status**: open | under-review | incorporated | declined
- **Priority**: P0/P1/P2/P3 (or high/medium/low)
- **Phase-fit**: which repo's MASTER_PLAN phase it might join, or "new phase"
- **Requested**: YYYY-MM-DD
- **Description**: what it does and why it's needed
- **Notes**: dependencies, alternatives, cross-repo touch points
```

- **ID scheme:** `FR-###` is a **single shared sequence across all repos** — keep
  IDs stable, never renumber (items are referenced by ID). Assign the next free
  number (see the "Next free ID" line at the top of `FEATURES.md`).
- Sections in the file (in order): `## Open Requests` → `## Under Review` →
  `## Incorporated (archive)` → `## Declined`.

## Commands (parse the args after `/feature`)

- **(no args / `list`)** → pull, Read the file, render **Open Requests** grouped
  by priority with their `Repo(s)/area` tag and a one-line count summary at top
  (e.g. "10 open — 1 high / 6 med / 3 low; repos: 7 reservations, 3 FM V3").
  Don't dump the Incorporated archive unless asked. End by offering the next action.
- **`add <description>`** → **size check FIRST**: if the description is a small,
  already-defined fix / tweak / one-line change / contained UI affordance / ops
  chore, it is NOT a feature — say so and offer `/todo add` instead (don't file
  it as an FR). Only for genuinely large/undefined work: infer the `Repo(s)/area`
  from the text (ask if ambiguous), assign the next `FR-###`, append under
  **Open Requests**, bump the "Next free ID" line, echo the added entry, then
  commit + push.
- **`review`** → for each open request assess alignment with the repo's goals,
  technical complexity, dependencies, user impact, and **right backlog?** (if it
  shrank to a small defined task, move to `/todo`; flag `/todo` items that should
  be promoted up to here). Recommend priority + next steps. If a feature has been
  built, move it to **Incorporated (archive)** with the repo + phase it joined.
- **`<filter>`** (e.g. `/feature reservations`, `/feature high`, `/feature FR-037`)
  → show only matching items.
- **`incorporate <ID> <repo phase>`** → move the item to the Incorporated table
  with its repo + target phase + today's date (from the environment context,
  never guess). Full detail stays in git history.
- **`edit <ID> <text>`** / **`decline <ID> <reason>`** → update, or move to the
  Declined table with a reason + date (confirm first).

## Auto-review during planning

When entering plan mode for a new feature, pull + check `FEATURES.md` for open
requests that overlap with or inform the current work, and surface them. Also
cross-check the relevant repo's `docs/MASTER_PLAN.md` so a feature isn't filed
twice or built without noticing an existing FR.

## Behavior notes

- **Read-mostly + small targeted edits.** The only git it does is the backlog-file
  pull/commit/push for cross-machine sync; it never touches product-repo code or
  opens PRs. If acting on a feature turns into real work, that follows the normal
  rules (`/letsbuild`, worktree, PR) — `/feature` just tracks it.
- Keep IDs stable; preserve the file's comments/structure and the per-repo tags.
- Items tagged for a specific repo may also be tracked in that repo's
  `MASTER_PLAN.md` once incorporated — `/feature` is the cross-repo intake/roadmap
  view; the master plan is the per-repo execution view.
