---
name: handoff
description: Session checkpoint / rotate / orient. Captures what this window is building (feature, phase, next action, open threads, key pointers) into a dense snapshot so you can /clear the giant context and resume in the SAME window without losing your place — killing the cache-tax of marathon sessions while keeping continuity. Also orients across ALL windows ("what's being built where, and where is M?"). Invoke with /handoff (checkpoint+rotate this window), "/handoff where" (cross-window roll-up), "/handoff resume" (re-seed a freshly cleared window), "/handoff prune" (archive stale registrations), "/handoff list". Use whenever the user says /handoff, "checkpoint", "rotate this session", "save my place", "where am I", "what's being built where", "where's M", "I'm lost", or when a session is going marathon (statusline ⟳ rotate). Complements /pm (reads its rosters) — does not replace it.
---

# /handoff — checkpoint, rotate, and orient

## ⛔ OUTPUT FORMAT — HARD RULE for every mode, no exceptions

**Recap first, then numbered paste-order next steps. Nothing else leads.** Governs `/handoff`,
`resume`, `where`, `list` — every mode, and every snapshot you write.

**Canonical spec — the ONLY full copy — is `~/.claude/skills/sitrep/FORMAT.md`** (required shape,
worked example, failure modes, the why). Read it before your first handoff in a session; change
the rule THERE, never here. Compressed, so you comply even without the read:

1. **Recap first, always.** What the project is + where we are. ≤6 lines. Never open with
   findings, history, or reasoning.
2. **Then numbered next steps in paste order** — "Step 1, Step 2, Step 3." Directly actionable:
   a paste-ready prompt, an exact command, a specific decision. If several windows need
   launching, stage them in the order the user should paste them.
3. **Say which step matters most** if one dominates.
4. **Analysis lives in the artifacts, not the reply** — snapshots, `~/.claude/pm/<project>/`,
   review reports. Reference by path.
5. **Every PR carries its full URL**, never a bare `#number` (memory: `always-give-pr-link`).

Self-trigger: if the reply opens with anything before the recap, stop and rewrite it. Mike acts
on this output — a handoff that doesn't say what to do next has failed at its only job.
(Memory: `m-next-step-reporting`.)

Solves the marathon-session problem: long windows re-read a 300k+ context every turn
(~84% of token cost — see memory `context-cache-dominates-cost`). Rotating fixes it, but
rotating loses your place. `/handoff` captures your place into a ~3k snapshot so you can
`/clear` and keep working in the SAME window.

The engine is `~/.claude/handoff.sh`. The SCRIPT gathers hard facts; YOU (the model) write
the narrative, because only this live session knows "we just did X, next is Y, blocked on Z."

## Modes

### `/handoff` (default) — checkpoint & rotate THIS window
1. Run `~/.claude/handoff.sh gather` (pass the worktree path if not in cwd). It prints hard
   facts: branch, worktree, uncommitted count, recent commits, open PR#, the registry row,
   MEMORY hits, this window's **anchor**, and the snapshot spec + exact target path.
2. Compose a DENSE snapshot from those facts PLUS what only this conversation knows. The
   script pre-fills the header with real `branch:`/`worktree:`/`anchor:`/`updated:` values —
   fill the rest (window/role/feature/phase/pr/next) and the sections (What's being built /
   Current state / Next action / Open threads / Key pointers). **Copy `anchor:` verbatim** —
   it binds this snapshot to THIS window so resume finds it and not another project's.
   **Write** it to the EXACT path the script printed (it embeds `--a<anchor>-<stamp>`, so it
   never overwrites another window's checkpoint or an earlier one of your own).
   `gather` also refreshes this window's project record (`~/.claude/windows/a<anchor>.json`)
   with the current branch/worktree. After you Write the snapshot, run the one-line
   `window-context.sh write project=… phase=… next=… pr=…` the script prints — that stamps
   the live situation onto the record so `/sitrep` (and the statusline chip) read it cheaply
   instead of re-deriving. Fail-open: skip silently if the script isn't present.
3. Print the snapshot back, then tell the user verbatim:
   > ✅ Checkpoint saved: `<path>`. Now run **`/clear`** (full context reset — the big cache
   > saving), then **`/handoff resume`** to pick up exactly here. Same window, clean context.
   Do NOT try to run /clear yourself — it's user-driven.

Keep the snapshot ruthless: goal + current state + the single next action + live blockers +
`file:line` pointers. No history narration that doesn't change what to do next.

### `/handoff resume` — re-seed a freshly cleared window
Run `~/.claude/handoff.sh resume`. It resolves which snapshot is THIS window's by the
**anchor** (the claude process, stable across `/clear`) — so it picks the right one even when
several windows share a branch and cwd (e.g. two M windows both on `staging` in the same
checkout). Read the snapshot and orient the user in 2-3 lines: "You're in <window> building
<feature>, phase <X>. Next action: <Y>. Open: <blockers>." Then continue from the Next action.

If the script instead prints **⚠️ multiple candidates** (this window has no anchor-matched
snapshot — e.g. saved before this fix, or the process restarted), it will NOT guess. Relay the
candidate list and ask the user which project, then re-run `handoff.sh resume <slug-or-word>`
(any word from that snapshot's feature line) to load the right one. Never hand-pick silently.

### `/handoff where [days|all]` — orient across ALL windows
Run `~/.claude/handoff.sh where` (default = registrations from last 4 days; `where 14` for a
wider window; `where all` for everything). Relay the output. It shows: active windows by
branch (branch names the feature), M-tracked `/pm` projects and their rosters (where M is),
and the last checkpoint per window (phase + next action) from saved snapshots. This is the
"I'm lost / what's being built where / where's M" view. Cheap — just relay, don't re-analyze.

### `/handoff prune [days] [--apply]` — clean stale registrations
`active-work.md` accumulates registrations forever and every worktree copies them, so the
registry bloats with shipped work. `~/.claude/handoff.sh prune` (dry-run, default keep last
10 days) shows keep/archive counts per canonical repo; add `--apply` to move stale rows into
`active-work-archive.md` (non-destructive — nothing deleted, gate only sees live work).
Confirm the day-window with the user before `--apply` if it would archive recent rows.

### `/handoff list` — list saved snapshots

## Relationship to /pm and the cost work
- Reads `/pm` rosters for the `where` view; does not replace `/pm` orchestration.
- This is the missing tool that makes session rotation usable — the enforcement side of
  `context-cache-dominates-cost` and the doctrine "one feature per session" rule. Rotate at
  feature-complete (or when the statusline shows `⟳ rotate`) instead of running to 900 turns.
