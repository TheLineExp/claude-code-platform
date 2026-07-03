# claude-code-platform — repo guide

Single source of truth for Mike's Claude Code dev system on this Mac. `~/.claude` is
generated FROM this repo — see docs/AUDIT-2026-07-02.md for why.

## Layout

- `platform/global/` — canonical layer synced to `~/.claude`:
  - `skills/` — 9 skills (doctrine, feature, graphify, letsbuild, pm, route, shipit, todo, traceability-review)
  - `agents/` — parity-sweep, money-concurrency-reviewer, traceability-reviewer
  - `backlog-gate.js` (PreToolUse hook), `statusline-command.sh`
  - `claude-CLAUDE.template.md` → `~/.claude/CLAUDE.md`; `claude-settings.template.json` → `~/.claude/settings.json`
  - `graphify-autoquery.js` — retired from deployment; kept in repo only
- `setup-machine.sh` — the ONLY writer of `~/.claude`. Default = sync (with backup); `--diff` = report drift, no writes
- `docs/` — architecture, setup, reference
- `backlog/` — cross-repo /todo + /feature store

## Hard rules

1. **Never hand-edit `~/.claude`.** Edit `platform/global/` here, then run
   `./setup-machine.sh`. Hand edits are overwritten on next sync and never reach git.
2. **Keep `platform/global/skills/*` and `~/.claude/skills/*` identical.** Run
   `./setup-machine.sh --diff` before committing; resolve any drift first.
3. Paths under `/Users/mikekunz/Documents/Volo Technologies/` contain a space — always
   quote them (space-free symlink: `~/vt`).
4. gstack-ship / gstack-review are retired; there is no azure-ops repo. Don't reintroduce
   references.
