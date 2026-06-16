---
name: todo
description: Personal running QUALITY-SWEEP backlog across ALL FleetManager repos (reservations / FM V3 / vouchers / azure-ops) — small, well-defined, lower-priority fixes/tweaks and ops/cleanup that can be batched into a quality sweep. Persistent + file-backed + cross-repo. Invoke with /todo to view the list; "/todo add ...", "/todo done ...", "/todo <filter>" to manage it. Use whenever the user says /todo, "my todos", "the backlog", "what's on my list", "add a follow-up", or wants to park/recall a small functional task. Distinct from /feature (LARGE, undefined projects that add functionality or redesign the product) and MASTER_PLAN.md (phase/planning tracking).
---

# /todo — running quality-sweep backlog

A single persistent, cross-repo list of **small, well-defined, lower-priority
work** on the system — the kind of items that can be batched into a "quality
sweep." It is the user's (Michael's) personal backlog and the front door for
fast follow-ups/fixes and ops/cleanup.

**Scope boundary (this is the line that separates `/todo` from `/feature`):**
- `/todo` owns work that is **small + already defined** — a fix, a tweak, a
  one-line policy change, a contained UI affordance, an ops/cleanup chore. You
  could hand it to a dev and they'd know what to build. Groupable into a
  quality sweep.
- `/feature` owns work that is **large + undefined** — net-new capabilities or
  product redesigns that need scoping/design before anyone can build them
  (multi-PR projects). If an item needs a design pass, it's a `/feature`, not a
  `/todo`.

It is **separate** from `/feature` (large/undefined projects) and from
`MASTER_PLAN.md` (planning/phase tracking).

## Backing file (single source of truth)

The list lives in the **git-synced** unified backlog so it spans every dev
machine. Resolve the location at runtime:

1. Read `~/.claude/backlog-location` — a one-line file written by
   `setup-machine.sh` holding the absolute path to the backlog dir on THIS
   machine (the `backlog/` dir inside the `claude-code-platform` repo clone).
2. The todo list is `<backlog-dir>/TODO.md`.
3. **Fallback** if `~/.claude/backlog-location` is missing (machine not
   bootstrapped yet): look for a `claude-code-platform/backlog/TODO.md` under
   the dirs listed in `~/.claude/settings.json` `additionalDirectories`. If
   still not found, tell the user to run `bash setup-machine.sh` in the
   platform repo, and don't silently fall back to a local-only file.

**Cross-machine sync (do this every time):**
- **Before reading:** `git -C <backlog-dir> pull --ff-only` so you see edits
  made on other machines. If the pull fails (offline / conflict), warn and
  proceed with the local copy — never block the user.
- **After writing:** stage + commit + push just the backlog file:
  `git -C <backlog-dir> add TODO.md && git -C <backlog-dir> commit -m "todo: <what changed>" && git -C <backlog-dir> push`.
  The platform repo's `main` is unprotected and these are data-only edits, so a
  direct push is correct here — do NOT open a PR for routine list edits. If the
  push fails, tell the user the change is committed locally but unpushed.

Always **Read** it first, operate on it, then **Edit/Write** it back. Never keep
the list only in the session — it must persist to that file. If the file is
missing, create it from the template in the "File format" section below.

Sections (priority order): `🔥 Fast follow-ups` → `🧹 Ops / cleanup` →
`✅ Done (recent)`.

Item line format:
`- [ ] (ID) [repo-or-area] **title** — short note / link`

- **ID scheme:** `FF#` fast follow-up/fix, `OPS#` ops/cleanup. IDs are stable —
  assign the next free number in that class; **never renumber** existing items
  (the user references them by ID).
- **Retired class — `NF#` "new feature set":** large/undefined projects no
  longer live here; they moved to `/feature` (the backlog file keeps a
  `NF# → FR-###` trace map under a "Migrated" note). If a `/todo` item grows
  into a real project, hand it to `/feature` rather than re-adding an `NF#`.
- `[repo-or-area]` is one of `reservations`, `FM V3`, `vouchers`, `azure`,
  `all repos`, or a sensible area tag.

## Commands (parse the args after `/todo`)

- **(no args)** → Read the file and render the list grouped by section, open
  items first, with a one-line count summary at top
  (e.g. "9 open — 6 fast / 3 ops"). Keep it scannable. Do NOT dump the Done
  section unless asked. End by offering the next obvious action.
- **`add <text>`** → Add a small, well-defined fix/tweak/cleanup. Infer the
  section (FF# fast-fix vs OPS# ops) + repo from the text. **If the text
  describes a LARGE or undefined project — a new capability, a redesign, a
  multi-PR effort, or anything that needs scoping/design — it belongs in
  `/feature`, not here.** Say so and offer to run `/feature add` instead (don't
  silently file it as an FF#). Assign the next ID in the chosen class. Echo the
  added line.
  - `add --ops <text>` / `add --fast <text>` force the section.
- **`done <ID|fuzzy text>`** → Mark `[x]`, move it under "✅ Done (recent)" with
  a `(YYYY-MM-DD)` stamp (get today's date from the environment context, never
  guess). Confirm which item matched.
- **`<filter>`** (e.g. `/todo ops`, `/todo vouchers`, `/todo FM V3`) → show
  only matching items.
- **`import`** → scan the relevant repo's `docs/MASTER_PLAN.md` (and the user's
  memory "Active workstreams" index) for lines marked REMAINING / PENDING /
  deferred / TODO, propose the **small/defined** ones as candidate FF#/OPS#
  items grouped by class, and add the ones the user confirms. Route any
  **large/undefined** candidates to `/feature` instead of adding them here. Do
  not bulk-add silently.
- **`edit <ID> <new text>`** / **`rm <ID>`** → update or remove an item (confirm
  on `rm`).

## Behavior notes

- This skill is **read-mostly + small targeted edits** — no code changes. The
  only git it does is the backlog-file pull/commit/push for cross-machine sync
  (above); it never touches product-repo code or opens PRs. If acting on an item
  turns into real work, that work follows the normal rules (`/letsbuild`, etc.) —
  `/todo` just tracks it.
- Keep edits minimal and preserve the file's comments/structure.
- When the user finishes a piece of parked work elsewhere, proactively offer to
  `/todo done` the matching item.
- Prune the Done section when it grows long (keep ~last 10), with the user's ok.

## File format (bootstrap template)

If `<backlog-dir>/TODO.md` does not exist (e.g. a freshly set-up machine),
create it from this template — an EMPTY backlog with the canonical structure —
then commit + push it so other machines pick it up. Do **not** seed it with
someone else's items; it starts empty and fills as the user adds work.

```markdown
<!-- Running QUALITY-SWEEP backlog. Maintained by the /todo skill (~/.claude/skills/todo/SKILL.md).
     Cross-repo. Persistent.
     SCOPE: small, well-defined, lower-pri fixes/tweaks + ops/cleanup — groupable into a quality sweep.
     Distinct from: /feature (LARGE, undefined projects that add functionality or redesign the product)
       and any planning/phase-tracking doc.
     Item format:  - [ ] (ID) [repo-or-area] **title** — short note / link
     ID scheme: FF# = fast follow-up/fix, OPS# = ops/cleanup. Keep IDs stable; never renumber.
     Mark done: change [ ] → [x] and move under "Done (recent)" with a YYYY-MM-DD stamp. -->

# 🗂️ Backlog — quality-sweep tasks for the system

_Last touched: <date> (created)_

## 🔥 Fast follow-ups
_(small, discrete, ship-soon items — fixes, tweaks, residuals)_

## 🧹 Ops / cleanup

## ✅ Done (recent)
<!-- move completed items here with a date; prune periodically -->
```
