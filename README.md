# claude-code-platform

**Single source of truth for Mike's Claude Code dev system.** One Mac (darwin), one owner.
Everything that lives in `~/.claude` is generated from this repo — never hand-edited.

Rationale for the current design: [docs/AUDIT-2026-07-02.md](docs/AUDIT-2026-07-02.md) — the
two-week failure audit that killed per-repo skill copies, gstack, and graphify-autoquery.

## The system in one paragraph

Repos live in `/Users/mikekunz/Documents/Volo Technologies/` (path contains a **space** —
always quote it; a space-free symlink `~/vt` exists). The working repos are
`fleetmanager-reservations` (prod branch `master`), `Fleetmanager_V3` (prod branch `main`),
`fleetmanager-vouchers` (prod branch `master`), and this repo. The canonical config layer is
`platform/global/` here; `setup-machine.sh` syncs it into `~/.claude`. Fleet repos carry only
guard hooks — no per-repo skills or agents.

## What's in `platform/global/` (the canonical layer)

| Piece | Contents |
|-------|----------|
| `skills/` (9) | `doctrine`, `feature`, `graphify`, `letsbuild`, `pm`, `route`, `shipit`, `todo`, `traceability-review` |
| `agents/` (3) | `parity-sweep` (blast-radius / sibling-call-site sweeper), `money-concurrency-reviewer` (adversarial TOCTOU/race reviewer for money paths), `traceability-reviewer` (end-to-end call-chain checker) |
| `backlog-gate.js` | PreToolUse hook — confirms every `/todo` / `/feature` add (Doctrine Rule 4) |
| `statusline-command.sh` | Statusline |
| `claude-CLAUDE.template.md` | → `~/.claude/CLAUDE.md` |
| `claude-settings.template.json` | → `~/.claude/settings.json` |

`graphify-autoquery.js` remains in the repo but is **retired from deployment** — its entity
extraction injected junk graph nodes into every prompt.

## Quick start

```bash
cd "/Users/mikekunz/Documents/Volo Technologies"    # or: cd ~/vt
git clone <this-repo> claude-code-platform
cd claude-code-platform
./setup-machine.sh          # sync platform/global -> ~/.claude (backs up what it overwrites)
```

Restart Claude Code afterward so it picks up `~/.claude/settings.json`.

## Changing the system

`setup-machine.sh` is the **only** writer of `~/.claude`. Hand-editing `~/.claude` is
forbidden — edits there get silently overwritten on the next sync and never reach git.

1. Edit the file under `platform/global/` (or templates) **here**.
2. `./setup-machine.sh` to sync.
3. Commit.

## Drift checking

```bash
./setup-machine.sh --diff   # no writes; prints IDENTICAL/DIFFERS/MISSING/STRAY; exit 1 on drift
```

Run this before committing. If `--diff` reports drift you didn't make here, someone
hand-edited `~/.claude`: port the change into `platform/global/` if it's wanted, then re-sync.

## Per-repo layer (fleet repos)

Fleet repos get **only** guard hook scripts (`.claude/hooks/block-*.sh`,
`enforce-worktree.sh`, etc.) plus the settings wiring that binds them. No per-repo skills or
agents — those were deleted after drifting into three divergent copies (see the audit).

## Workflow pathways — exactly one per task

| Task | Pathway |
|------|---------|
| Start work | `/letsbuild` — worktree + branch + registration; doctrine plan-gate at Phase 0 |
| Ship | `/shipit` — staging PR → prod PR. Gates: `parity-sweep` + `money-concurrency-reviewer` agents, doctrine ship backstop, **PR-Ready gate** (checks green + 0 unresolved review threads before any "ready" claim), **prod-promotion gate** (staging must be converged first), session rotation after ship |
| Review | built-in `/code-review` + the three agents above |
| Backlog | `/todo` (small) / `/feature` (large) — both gated by the `backlog-gate` hook |

`gstack-ship` and `gstack-review` are retired.

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the two layers fit together
- [docs/SETUP.md](docs/SETUP.md) — machine setup detail
- [docs/NEW_PC.md](docs/NEW_PC.md) — fresh-Mac runbook
- [docs/SKILLS_REFERENCE.md](docs/SKILLS_REFERENCE.md) — the 9 skills + 3 agents
- [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md) — adding/changing skills, agents, hooks
- [docs/REVIEWS.md](docs/REVIEWS.md) — PR review convention
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — common failures
- [docs/AUDIT-2026-07-02.md](docs/AUDIT-2026-07-02.md) — why the system looks like this
