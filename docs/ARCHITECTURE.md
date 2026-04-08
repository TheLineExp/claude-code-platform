# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Claude Code Session                    │
│                                                          │
│  User Message → Claude → Tool Call → Hook Check → Execute│
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │ PreToolUse│  │PostToolUse│  │PreCompact │              │
│  │  9 hooks  │  │ tracker  │  │ notifier  │              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
│       │              │              │                     │
│  ┌────▼─────┐  ┌────▼─────┐  ┌────▼─────┐              │
│  │ Safety   │  │ Session  │  │ Context  │              │
│  │ + Config │  │ Counter  │  │ Rules    │              │
│  └────┬─────┘  └──────────┘  └──────────┘              │
│       │                                                  │
│  ┌────▼──────────────────┐                              │
│  │ PostToolUseFailure    │                              │
│  │ Error Handler         │                              │
│  │ (one-try fingerprint) │                              │
│  └───────────────────────┘                              │
└─────────────────────────────────────────────────────────┘
```

## Hook Execution Flow

### PreToolUse (before every tool call)

**On Bash commands** — all 9 hooks run in order:
1. `block-protected-branch.sh` — is this a `git commit` on a protected branch?
2. `block-no-verify.sh` — does the command contain `--no-verify`?
3. `block-destructive-git.sh` — force push, hard reset, checkout .?
4. `block-gh-merge.sh` — is this `gh pr merge`?
5. `block-rebase-interactive.sh` — interactive rebase or add?
6. `block-file-redirect.sh` — file write via redirect in main repo?
7. `check-work-registration.sh` — is this branch registered?
8. `check-branch-prefix.sh` — does branch prefix match window ID?
9. `enforce-worktree.sh` — is the file in the main repo?

**On Edit/Write** — only `enforce-worktree.sh` runs.

**Fast-path optimization**: `_parse-input.sh` sets `NEEDS_GIT_CHECK` flag. Non-git commands skip hooks 1-5, 7-8.

### PostToolUse (after every tool call)

`session-tracker.sh` increments a counter in `/tmp/` and injects guidance at thresholds.

### PostToolUseFailure (after failed tool calls)

`error-handler.sh` fingerprints the error. First occurrence → provides fix guidance. Repeated → escalates to user (one-try rule).

### PreCompact (before context compression)

`compact-notifier.sh` injects critical rules that must survive compaction.

## Configuration Flow

```
platform.config.json
       │
       ├──→ _config.sh (loaded by hooks)
       │      exports: PROTECTED_BRANCHES, FEATURE_PREFIX, etc.
       │
       ├──→ setup.sh (generates settings.json, CLAUDE.md)
       │
       └──→ Skills (read at runtime for repo name, branches, URLs)
```

## Worktree Isolation

```
my-project/          # Main repo — setup only, never code here
  ├── .claude/       #   Editable (hooks, skills, settings)
  └── src/           #   BLOCKED by enforce-worktree.sh

my-project-w1/       # Agent 1 worktree — full access
  ├── .claude/       #   Copied from main repo
  └── src/           #   All edits happen here

my-project-w2/       # Agent 2 worktree — independent
```

## Permission Layers

```
Deny rules (hard floor — cannot be overridden)
  ↑
settings.json allow rules (project-wide)
  ↑
settings.local.json allow rules (personal overrides)
  ↑
Hook checks (run even on allowed commands)
```

## Addon Pattern

```
Platform skill (generic)          Project addon (specific)
┌─────────────────────────┐      ┌──────────────────────────┐
│ /code-review            │      │ code-review-addons.md    │
│                         │ reads│                          │
│ Generic checklist:      │──────│ Project-specific checks: │
│ - No debug statements   │      │ - PII encryption         │
│ - Error handling        │      │ - HMAC hashes            │
│ - Single responsibility │      │ - Audit logging          │
└─────────────────────────┘      └──────────────────────────┘
```

Platform updates merge cleanly because addon files are separate.
