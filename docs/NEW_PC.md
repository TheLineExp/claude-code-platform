# New-Mac Setup

Copy-paste runbook to stand up the full dev environment on a fresh Mac. The system is
single-machine (darwin) and single-owner; there are no Windows or Linux instructions.

Two layers, in order: **machine layer** (`setup-machine.sh` → `~/.claude`), then **repo
layer** (clone repos + their git hooks + `.env` scaffolding). No secrets live in this repo
— everything is re-authed live (§3).

## 0. Prerequisites

Install (Homebrew for most):

| Tool | Notes |
|------|-------|
| Xcode CLT / git | `xcode-select --install` |
| Node 22+ | needs `--env-file` / `--watch` |
| Docker Desktop | per-repo docker stacks |
| `gh` | GitHub CLI |
| `az` | Azure CLI — deployments / container apps |
| `jq` | required — `setup-repos.sh` parses `repos.json` with it |
| VS Code | each repo ships `.vscode/extensions.json` |
| Claude Code | CLI or VS Code extension |
| Codex CLI | optional — part of the dual-review setup ([REVIEWS.md](REVIEWS.md)) |
| Graphify | optional — powers `/graphify` |

## 1. Repos root + platform repo

Repos live in `/Users/mikekunz/Documents/Volo Technologies/` — the path contains a
**space**, so quote it everywhere; also create the space-free symlink:

```bash
mkdir -p "/Users/mikekunz/Documents/Volo Technologies"
ln -sfn "/Users/mikekunz/Documents/Volo Technologies" ~/vt
cd ~/vt
git clone https://github.com/TheLineExp/claude-code-platform.git
cd claude-code-platform
```

## 2. Machine layer

```bash
./setup-machine.sh
```

Syncs `platform/global/` → `~/.claude` (settings, CLAUDE.md, 9 skills, 3 agents,
backlog-gate hook, statusline), substituting real machine paths and backing up anything it
overwrites. Details: [SETUP.md](SETUP.md). Then **restart Claude Code**.

Verify: `./setup-machine.sh --diff` → everything IDENTICAL.

## 3. Secrets — re-auth checklist

```bash
claude login       # ~/.claude/.credentials.json
gh auth login      # GitHub (PRs, gh api)
az login           # Azure; confirm access to resource group fleetmanager-rg
codex login        # only if using Codex review
```

Per-repo `.env` values (dev keys; prod comes from Azure `secretref:`). Paste from the
password manager / Key Vault after step 4 scaffolds each `.env` — never commit them:

- `PII_ENCRYPTION_KEY`, `LICENSE_ENCRYPTION_KEY` — 32-byte hex
- `JWT_SECRET` — **must match FM V3** for SSO
- `RESERVATIONS_DATABASE_URL`, `FLEETMANAGER_DATABASE_URL`

## 4. Repo layer

```bash
bash setup-repos.sh    # reads repos.json
```

Per repo: clones if absent, installs that repo's git hooks, scaffolds `.env` from
`.env.example`. The repos (there is no azure-ops repo):

| Repo | Prod branch |
|------|-------------|
| `fleetmanager-reservations` | `master` |
| `Fleetmanager_V3` | `main` |
| `fleetmanager-vouchers` | `master` |
| `claude-code-platform` | (this repo) |

Fleet repos carry **only guard hooks** in `.claude/hooks/` — skills and agents all come
from the machine layer.

## 5. Validate

```bash
./setup-machine.sh --diff                         # clean
ls ~/.claude/skills                                # the 9 skills
ls ~/.claude/agents                                # the 3 agents
cd ~/vt/fleetmanager-reservations && ls .git/hooks/pre-commit
```

In Claude Code: statusline shows `dir (branch) model ctx:NN%`; in a fleet repo,
`/letsbuild` creates a worktree; `/todo add test` triggers the backlog-gate confirm prompt.

## 6. Review workflow

See [REVIEWS.md](REVIEWS.md) — local `/code-review --comment` as primary, plus the
`parity-sweep` / `money-concurrency-reviewer` / `traceability-reviewer` agent gates run by
`/shipit`.
