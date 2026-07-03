# Troubleshooting

## `--diff` reports drift

```bash
./setup-machine.sh --diff
```

- **DIFFERS / STRAY** and you didn't change the repo → `~/.claude` was hand-edited. Decide:
  port the live change into `platform/global/` (if it's wanted) or discard it. Then
  `./setup-machine.sh` to re-converge. Never leave drift standing — it silently forks the
  system.
- **MISSING** → run a plain `./setup-machine.sh` sync.

## A skill or agent behaves like an old version

`~/.claude` is stale. `./setup-machine.sh`, then restart Claude Code (settings and skills
load at startup).

## backlog-gate doesn't prompt on `/todo` / `/feature` adds

1. `ls ~/.claude/hooks/backlog-gate.js` — missing → re-sync.
2. Check it's registered: `grep backlog-gate ~/.claude/settings.json` (PreToolUse → Skill).
3. Restart Claude Code. The hook fails open by design, so a broken hook = silent adds —
   fix it rather than living with it.

## `/todo` or `/feature` can't find the backlog

`cat ~/.claude/backlog-location` — it must contain this repo's `backlog/` path.
`setup-machine.sh` writes it; re-run if missing or pointing at an old clone.

## Commands fail with "no such file or directory" on repo paths

The repos root `/Users/mikekunz/Documents/Volo Technologies/` contains a **space**. Quote
every path, or use the space-free symlink `~/vt`.

## Guard hooks not firing in a fleet repo

Guard hooks live in each fleet repo, not here.

```bash
ls -la .claude/hooks/*.sh          # present?
chmod +x .claude/hooks/*.sh        # executable?
grep -A5 PreToolUse .claude/settings.json   # wired?
```

## "BLOCKED: file is inside the main repo" / "branch not registered"

Working as intended — you're editing in the main checkout or on an unregistered branch.
Run `/letsbuild`; it creates the worktree, branch, and registration in one step.

## `/shipit` refuses to call a PR "ready"

The PR-Ready gate requires **checks green + zero unresolved review threads** on the current
HEAD. Fix or reply-and-resolve every thread, wait for checks, retry. The prod-promotion
gate additionally requires staging to be converged before a prod PR.

## Statusline missing

`ls -la ~/.claude/statusline-command.sh` (must exist and be executable; re-sync if not),
and confirm `statusLine` in `~/.claude/settings.json` points at it.

## Junk "[graphify auto-consult]" blocks in prompts

Shouldn't happen anymore — `graphify-autoquery.js` is retired. If you see it,
`rm ~/.claude/hooks/graphify-autoquery.js`, remove any reference to it from
`~/.claude/settings.json`, and check `--diff`: a stale sync or hand edit reinstalled it.

## When in doubt

`./setup-machine.sh` (it backs up before overwriting), restart Claude Code, re-check
`--diff`. The repo is the truth; `~/.claude` is disposable.
