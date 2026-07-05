# Changing the System

Everything flows one way: **edit `platform/global/` here → `./setup-machine.sh` → commit.**
Never hand-edit `~/.claude` — the next sync overwrites it and the change never reaches git.
Run `./setup-machine.sh --diff` before committing to confirm repo and `~/.claude` are
identical.

## Edit an existing skill

1. Edit `platform/global/skills/<name>/SKILL.md` (and any support files in that dir).
2. `./setup-machine.sh` — syncs it to `~/.claude/skills/<name>/`.
3. `./setup-machine.sh --diff` to verify, then commit.

## Add a new skill

1. Create `platform/global/skills/your-skill/SKILL.md`:

   ```markdown
   ---
   name: your-skill
   description: What it does and when to use it. Claude matches on this — make triggers explicit.
   user_invocable: true
   ---

   # Your Skill

   ## Workflow
   1. ...
   ```

2. Sync + verify + commit as above. Available as `/your-skill` after restart.

If the new skill is a workflow pathway (start/ship/review/backlog), keep "exactly one
pathway per task": update README's pathway table and make sure it doesn't overlap an
existing one.

## Add or edit an agent

Agents live in `platform/global/agents/<name>.md`:

```markdown
---
name: your-agent
description: What it does and when Claude should invoke it proactively.
tools: Read, Grep, Glob, Bash
model: inherit
---

Instructions...
```

Same flow: edit → sync → `--diff` → commit. Keep review agents read-only (`Read, Grep,
Glob, Bash`) — they report, they don't fix.

## Add or edit a global hook

1. Put the script in `platform/global/` (see `backlog-gate.js` for the pattern — it's a
   PreToolUse(Skill) hook that fails open).
2. Register it in `platform/global/claude-settings.template.json` under the right event.
   There is NO template substitution — `setup-machine.sh` plain-copies this file to
   `~/.claude/settings.json`. Write hook commands with `~` (`bash ~/.claude/hooks/x.sh`,
   `node ~/.claude/hooks/x.js`); the shell expands `~` when the hook runs, so the command is
   not locked to one user's home. Permission globs / `additionalDirectories` are the one place
   literal machine paths are unavoidable (they name this Mac's repo locations) — fine for this
   single-machine platform.
3. Ensure `setup-machine.sh` copies it (it syncs the known file list — if you add a new
   top-level file, add the copy step there too; setup-machine.sh is owned outside docs/,
   so coordinate that edit).
4. Sync, restart Claude Code, verify the hook fires, commit.

## Change settings / permissions

Edit `platform/global/claude-settings.template.json`, not `~/.claude/settings.json`.
Placeholders are substituted at sync time.

## Per-repo guard hooks (fleet repos)

Guard hooks (`block-*.sh`, `enforce-worktree.sh`, ...) are versioned inside each fleet repo
under `.claude/hooks/` with their settings wiring. Edit them in that repo, not here. Do
NOT add per-repo skills or agents — that pattern drifted into three divergent copies and
was deliberately removed (see [AUDIT-2026-07-02.md](AUDIT-2026-07-02.md)).

## Retiring something

Deleting from `platform/global/` does not delete from `~/.claude` automatically — after
removing a skill/agent, check `--diff` for STRAY entries and remove the live copy, or let
the next full sync handle it if it does. Precedent: `graphify-autoquery.js` stays in the
repo but is excluded from deployment; `gstack-ship`/`gstack-review` were deleted outright.
