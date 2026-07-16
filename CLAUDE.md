# claude-code-platform — repo guide

Single source of truth for Mike's Claude Code dev system on this Mac. `~/.claude` is
generated FROM this repo — see docs/AUDIT-2026-07-02.md for why.

## Layout

- `platform/global/` — canonical layer synced to `~/.claude`:
  - `skills/` — doctrine, feature, graphify, handoff, letsbuild, pm, route, shipit, todo, traceability-review (canonical roster + counts: docs/SKILLS_REFERENCE.md)
  - `agents/` — parity-sweep, money-concurrency-reviewer, traceability-reviewer,
    project-evaluator (letsbuild Phase 0.5 sizing gate: every project SOLO vs /pm-default),
    outside-reviewer (shipit Step 4b context-isolated pre-push review, every ship)
  - `hooks/` — the git-safety guard hooks (block-*, check-*, enforce-worktree, deps
    `_parse-input.sh`/`_config.sh`/`_tokenize.pl`). GLOBAL: they fire for every session via
    `~/.claude/settings.json`, not per-repo. Universal guards (no-verify, destructive-git,
    gh-merge, rebase) run everywhere; worktree-discipline hooks self-gate on a registered
    `.claude/active-work.md` (via `_fleet_active`), while block-protected-branch gates on a
    `.claude/` dir existing (`_fleet_shaped` — fail-CLOSED even if active-work.md is emptied;
    audit A8). ONE exemption: a config/data TRUNK repo listed in `$TRUNK_REPOS` (`_config.sh`;
    this repo) — whose `main` is the intended direct-push workflow (the `/feature`+`/todo`
    backlog `commit && push` flow) — is NOT deploy-branch-protected, matched by origin-remote
    or worktree basename via `_is_trunk_repo` (fail-CLOSED; product repos are never listed).
    Guards match on the normalized ARGV MODEL emitted by ONE shell-faithful
    tokenizer (`_tokenize.pl`, sourced via `_parse-input.sh`) — never string regex, so the
    git and writer surfaces cannot drift and a flag literal inside a quoted `-m` message is
    just one token the guard skips (audit A9). Policy (`_config.sh`) is hardcoded — no
    platform.config.json. `_tokenize.pl` is a hard dependency: setup-machine.sh mirrors
    `*.sh` + `*.pl`, and without it the guards fail OPEN.
    **Any hook edit must run `platform/tests/hook-bypass-suite.sh` (250) AND
    `platform/tests/hook-grammar-fuzz.sh` (CLEAN) before AND after — canonical and live.
    Edits to the advisory hooks (`check-fix-landed.sh`, `pr-ready-gate.js`) must also run
    `platform/tests/advisory-hooks.test.sh`.**
  - `backlog-gate.js` (PreToolUse hook), `session-guard.js` (UserPromptSubmit),
    `check-fix-landed.sh` (PostToolUse advisory: after a git commit/push, loudly flags an
    ORPHANED fix — pushed to an already-merged/closed PR branch, or no PR — so a fix can't
    silently miss deploy; never blocks), `pr-ready-gate.js` (Stop hook + `verify` CLI: the
    real PR-Ready gate — blocks a "ready/done/shipped" claim about a PR with no fresh
    `gh pr checks`-green + 0-unresolved-threads marker; shipit Step 5b writes the marker),
    `statusline-command.sh`, `handoff.sh` (engine for the `handoff` skill)
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
