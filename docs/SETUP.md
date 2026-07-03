# Setup

One machine (Mike's Mac), one script. For a from-scratch Mac, use
[NEW_PC.md](NEW_PC.md); this page covers the platform repo itself.

## Prerequisites

- macOS with git, bash, and `jq`
- Claude Code (CLI or VS Code extension)
- `gh` (GitHub CLI), authenticated

## Install / sync

```bash
cd "/Users/mikekunz/Documents/Volo Technologies"     # or: cd ~/vt
git clone <this-repo> claude-code-platform            # if not already present
cd claude-code-platform
./setup-machine.sh
```

What it does (idempotent; backs up anything it overwrites to `*.bak-N`):

- Renders `platform/global/claude-settings.template.json` → `~/.claude/settings.json` and
  `platform/global/claude-CLAUDE.template.md` → `~/.claude/CLAUDE.md`, substituting real
  machine paths.
- Syncs the 9 skills → `~/.claude/skills/` and the 3 agents → `~/.claude/agents/`.
- Installs `backlog-gate.js` → `~/.claude/hooks/` and `statusline-command.sh`.
- Writes `~/.claude/backlog-location` pointing at this repo's `backlog/` dir.

Then **restart Claude Code** so it loads the new settings.

Note: `graphify-autoquery.js` is NOT deployed — it's retired (kept in `platform/global/`
for reference only).

## Drift check

```bash
./setup-machine.sh --diff
```

Read-only. Prints IDENTICAL / DIFFERS / MISSING / STRAY per file and exits 1 on drift. Run
it before every commit to this repo. Drift you didn't author means `~/.claude` was
hand-edited — port the change into `platform/global/` if it's wanted, then re-sync.

## The one rule

**Never hand-edit `~/.claude`.** `setup-machine.sh` is the only writer. Edit
`platform/global/` here, sync, commit.

## Fleet repos

Fleet repos (`fleetmanager-reservations`, `Fleetmanager_V3`, `fleetmanager-vouchers`) carry
only guard hooks (`.claude/hooks/block-*.sh`, `enforce-worktree.sh`, ...) plus settings
wiring — no skills or agents. Those are versioned inside each repo; nothing extra to set up
beyond cloning and each repo's own hook install.

## Path note

The repos root `/Users/mikekunz/Documents/Volo Technologies/` contains a space — quote it
in every command, or use the space-free symlink `~/vt`.
