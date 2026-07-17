---
name: sitrep
description: Situation report on any project — the recap + numbered paste-order next steps, on demand, from any window. Answers "where is this project and what do I do next?" without needing to be the M window or hold the project's context. Reads /pm artifacts, memory, and live GitHub PR state (every PR with its full merge URL). Invoke with /sitrep (THIS window's project), "/sitrep <project>" (any project, PM or memory-tracked — e.g. /sitrep vouchers, /sitrep w114, /sitrep x40), "/sitrep all" (roll-up of every project), "/sitrep prs" (open PRs everywhere with merge links). Use whenever the user says /sitrep, "status", "where are we", "where does this project stand", "what's next on X", "give me the rundown", "what should I do next", or asks for a project's state. Read-only — never mutates project state. Distinct from /pm status (M-only live roll-up that writes a report artifact) and /handoff where (cross-WINDOW view, not per-PROJECT).
---

# /sitrep — situation report on any project

Answers one question: **where is this project, and what do I do next?**

Any window, any project, no M context required. Read-only — it never writes project state.

## ⛔ OUTPUT FORMAT — HARD RULE

**Recap first, then numbered paste-order next steps. Nothing else leads.**

The canonical spec — required shape, worked example, failure modes — is
**`~/.claude/skills/sitrep/FORMAT.md`**. It is the ONLY full copy of the rule.
**Read it before writing your first sitrep in a session.** Compressed, so you comply even
without the read:

1. **Recap first** — what the project *is* + where we are. ≤6 lines. Never open with a finding.
2. **Numbered next steps in paste order** — "Step 1, 2, 3." Each is paste-ready: a prompt, an
   exact command, or a specific decision. Stage windows in the order Mike pastes them.
3. **Name the dominant step** — "If you only do one thing, do Step N."
4. **Analysis → artifacts, referenced BY PATH.** Never paste review bodies or brief bodies.
5. **Every PR carries its full URL** — `https://github.com/TheLineExp/<repo>/pull/<n>`, never a
   bare `#1574` (memory: `always-give-pr-link`).

## How it works

The **script gathers facts; YOU write the narrative.** Only a thinking read of the artifacts can
say "this is blocked behind that one thing, so Step 1 is X" — that judgment is the whole product.

```
~/.claude/skills/sitrep/sitrep.sh gather [project]   # facts for one project
~/.claude/skills/sitrep/sitrep.sh list               # every project, one line each
~/.claude/skills/sitrep/sitrep.sh prs                # open PRs everywhere + merge URLs
~/.claude/skills/sitrep/sitrep.sh resolve <name>     # resolve a name to a project dir
```

### `/sitrep` (default) — THIS window's project (NOT a machine-global guess)

The no-arg default resolves the project of **the window you're in**, via the shared
per-window resolver `~/.claude/window-context.sh` (the same anchor `/handoff` uses):

1. **Anchor** — this window's claude process has a record at `~/.claude/windows/a<pid>.json`
   carrying its project/chunk/branch/phase/next. If present, that's the answer — definitive,
   survives `/clear`.
2. **Branch/cwd fallback** — if no anchor record (e.g. after a reboot changed the PID), a
   UNIQUE live window matching this branch/worktree resolves it.
3. **Refuse** — if neither resolves (no record, or two windows match ambiguously), the script
   **refuses and lists candidates**. It does NOT fall back to `~/.claude/pm/.active-project`
   — that machine-global file is whatever last ran `/pm init`, and reporting it here was the
   bug (every window claimed the same project). When you see the refuse output, either run
   `/letsbuild` or `/handoff` in this window to register it, or use `/sitrep <project>`.

Then, as before: run `sitrep.sh gather`, **read the facts and think**, find the ONE thing
gating the most work (that's Step 1), and write the report per `FORMAT.md`.

**The cheap path.** When this window's record carries `phase`/`next`/`pr`, `gather` prints
them at the top ("THIS WINDOW's live record"). Lead the recap with that instead of
re-deriving the whole situation from the raw artifacts — but **still verify PRs live** (below);
a stale record is a lie, and "done" means verified.

### `/sitrep <project>` — any project
Fuzzy-matches `~/.claude/pm/`. On **AMBIGUOUS**, the script lists candidates and refuses to
guess — ask Mike which; never silently pick.

If no `/pm` dir matches, the script drops to **NON-PM MODE** (memory + live git/gh) — that's how
`/sitrep w114` or `/sitrep x40` work. Memory hits are ranked by name-stem overlap and marked
*VERIFY relevance* — they are leads, not facts. A no-match is not proof nothing exists; grep
`MEMORY.md` before concluding.

### `/sitrep all` — roll-up
Run `sitrep.sh list`. One line per project, plus the live windows (who is on what right now).
Then, per `FORMAT.md`: recap the portfolio, then numbered steps ordered by **what's actually
blocking the most work**, not by project name.

### `/sitrep prs` — open PRs everywhere
Run `sitrep.sh prs`. Every PR with its full merge URL, checks rollup, and merge state.

## Verify before you call anything mergeable

`sitrep.sh prs` uses a **list query**, and it lies in two specific ways:
- `mergeState: UNKNOWN` means GitHub hadn't computed mergeability — **not** "mergeable".
- The rollup can disagree with the live gate (observed: #1582 reads `checks: GREEN` while
  `mergeState: UNSTABLE`).

So: **before presenting ANY PR as a merge step**, confirm live at that moment —
`gh pr checks <n> --repo <repo>` all green **AND** zero unresolved review threads (thread query:
`/shipit` Step 5b). A stale "ready to merge" is a defect (CLAUDE.md: *"Done" means verified*).

**Merges are Mike's.** Hand him the URL and the command — always `--merge`, never `--squash`
(memory: `never-squash-merge`). Never merge for him.

## Hard rules

1. **Read-only.** Never write `status.md`, roster, or any project state. State changes go through
   `/pm verify`, `/pm ship`, `/pm blocked`. A sitrep that mutates state is a defect. (The window
   record under `~/.claude/windows/` is per-window runtime state, not project state — the write
   side lives in `/letsbuild`, `/pm`, and `/handoff`, never in `/sitrep`.)
2. **Never paste a brief body or a review body.** Reference by path — a step is a POINTER to
   `briefs/chunk-<id>.md` (`/pm brief` hard rule). Pasting bodies is what Mike explicitly does
   not want.
3. **`In flight: nothing` is a finding.** Say it out loud and make it the argument for Step 1.
   Idle windows are the most common reason a track stalls.
4. **Never invent a next step.** If the facts don't support one, say what's unknown and make
   Step 1 the thing that resolves it. When `gather` REFUSES (no window context), Step 1 is
   literally "register this window" — do not paper over it by guessing a project.
5. **Don't re-derive what the artifacts already decided.** Blocking gates and open risks in
   `status.md` are M's considered judgment — carry them forward, don't relitigate them.
6. **Absolute paths in every prompt you emit**, quoted (the repos path contains a space; `~/vt`
   is the space-free symlink). Every dev-window prompt names its working dir on line 1.

## Relationship to the other skills

| Skill | Question it answers | Writes? |
|---|---|---|
| **`/sitrep`** | Where is this PROJECT, what do I do next? Any window. | No |
| `/pm status` | M's live roll-up; saves `reports/<date>-status.md` | Yes |
| `/handoff where` | Where are my WINDOWS / where is M? | No |
| `/handoff` | Save my place so I can `/clear` | Yes (snapshot + window record) |

`/sitrep` is the read-only, any-window view. It does not replace `/pm` orchestration: it never
routes, verifies, or ships. When a step *is* an orchestration action, the step is the `/pm`
command for Mike (or M) to run.
