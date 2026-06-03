# New-PC Setup — full Claude Code + Codex + Graphify environment

This is the copy-paste runbook to stand up your **entire** development environment on a
fresh machine: VS Code, Claude Code, Codex, Graphify, the user-global config (skills, hooks,
permissions, statusline), and all your repos with their git hooks + `.env` scaffolding.

Two layers, in order:
1. **Machine layer** (`setup-machine.sh`) — user-global `~/.claude`, `~/.codex`, `~/.graphify`.
2. **Repo layer** (`setup-repos.sh` + per-repo `setup.sh`) — clone + hooks + env per repo.

Nothing secret is stored in this repo. Credentials are re-authed live (§ Secrets).

---

## 0. Prerequisites

Install these first (all must be on `PATH`):

| Tool | Notes |
|------|-------|
| Git | + Git Bash on Windows (the scripts are bash; run them from Git Bash / MSYS2) |
| Node 22+ | needs `--env-file` / `--watch`; `node -v` ≥ 22 |
| Docker Desktop | for the per-repo docker stacks |
| `gh` (GitHub CLI) | `gh auth login` below |
| `az` (Azure CLI) | deployments / container apps |
| `jq` | **required** — `setup-repos.sh` parses `repos.json` with it |
| VS Code | install the recommended extensions (each repo ships `.vscode/extensions.json`) |
| Claude Code | the CLI/extension you're reading this in |
| Codex CLI | optional but part of the dual-review setup |
| Graphify | optional; powers `/graphify` + the auto-consult hook |

Windows note: run every `bash …` command from **Git Bash**, not PowerShell. Paths in this
guide use forward slashes (`C:/Users/you/...`).

---

## 1. Clone the platform repo

```bash
cd /c/Users/you/Documents          # your repos root
git clone https://github.com/TheLineExp/claude-code-platform.git
cd claude-code-platform
```

---

## 2. Machine layer — user-global config

```bash
bash setup-machine.sh
# prompts for your repos root; or:
REPOS_ROOT=/c/Users/you/Documents bash setup-machine.sh
# preview without writing:
DRY_RUN=1 bash setup-machine.sh
```

What it does (idempotent — backs up anything it overwrites to `*.bak-N`):
- Writes `~/.claude/settings.json` from `platform/global/claude-settings.template.json`,
  **substituting your real `HOME` / repos root** so there are no hardcoded paths.
- Writes `~/.claude/CLAUDE.md` (the graphify-first protocol).
- Installs `~/.claude/hooks/graphify-autoquery.js` (resolves its own paths at runtime) and
  `~/.claude/statusline-command.sh`.
- Installs the user-global skills into `~/.claude/skills/`: `graphify`, `gstack-review`,
  `gstack-ship`, `route`, and `pm`.
- Seeds `~/.codex/config.toml` from the portable template (only if Codex is installed and
  no config exists yet).
- Reports Graphify status.

Then **restart Claude Code** so it loads the new `~/.claude/settings.json`.

---

## 3. Secrets — re-auth checklist (nothing is stored in the repo)

Run these live on the new PC:

```bash
claude login          # regenerates ~/.claude/.credentials.json
codex login           # regenerates ~/.codex/auth.json
gh auth login         # GitHub (PRs, gh api)
az login              # Azure; confirm access to resource group fleetmanager-rg
```

Environment variable for the cross-repo graph extract (optional, see § Graphify):
```bash
export ANTHROPIC_API_KEY=...    # add to your shell profile
```

Per-repo `.env` values (dev keys — prod comes from Azure `secretref:`). `setup-repos.sh`
scaffolds each `.env` from its `.example`; then paste the real values, sourced from your
password manager / Azure Key Vault (names only — never commit them):
- `PII_ENCRYPTION_KEY`, `LICENSE_ENCRYPTION_KEY` — 32-byte hex
- `JWT_SECRET` — **must match FM V3** for SSO
- `RESERVATIONS_DATABASE_URL`, `FLEETMANAGER_DATABASE_URL`

> First-run trust prompts: Codex will ask to trust each repo's `.codex/hooks.json` the
> first time you open it; that writes the `trusted_hash` entries back into `~/.codex/config.toml`.
> This is expected and machine-local.

---

## 4. Repo layer — clone + hooks + env for every repo

```bash
bash setup-repos.sh
# or: REPOS_ROOT=/c/Users/you/Documents bash setup-repos.sh
```

Reads `repos.json` and, per repo: clones (if absent), runs that repo's `hooks/install.sh`
(git pre-commit/commit-msg/pre-push + the `merge=union` attribute for the hook-bypass log),
scaffolds `.env` from `.env.example`, and registers the graphify post-commit hook.

To target a **different set of repos**, edit `repos.json` — that's the only change needed.
(The platform is repo-agnostic; the three FleetManager repos are just the default manifest.)

---

## 5. Graphify (optional, recommended)

The per-repo graph auto-refreshes free on every commit (AST-only post-commit hook,
installed in step 4). The **cross-repo GLOBAL graph** is a paid snapshot — build it when you
want cross-repo auto-consult:

```bash
# needs ANTHROPIC_API_KEY in env + the anthropic SDK in graphify's uv venv; ~$3–6/repo
graphify extract /c/Users/you/Documents/fleetmanager-reservations --backend claude --global --as reservations
graphify extract /c/Users/you/Documents/fleetmanager/Fleetmanager_V3 --backend claude --global --as fm-v3
graphify extract /c/Users/you/Documents/fleetmanager-vouchers      --backend claude --global --as vouchers
```

The graph lands at `~/.graphify/global-graph.json`; the `graphify-autoquery.js` hook picks it
up automatically. Override its location with `GRAPHIFY_GLOBAL_GRAPH` / the binary with
`GRAPHIFY_BIN` if your install differs.

---

## 6. Validate

```bash
# No machine paths leaked into the generated config (should only match example configs):
grep -ri "michaelkunz" ~/.claude/settings.json && echo "LEAK" || echo "clean"

# Platform integrity:
cd /c/Users/you/Documents/claude-code-platform && bash hooks/verify.sh

# Per repo: hooks installed + a feature flow works
cd /c/Users/you/Documents/fleetmanager-reservations
ls .git/hooks/pre-commit .git/hooks/commit-msg     # present
# In Claude Code, open the repo and run /letsbuild — it should create a worktree.

# Graphify (if built):
graphify query "reservation pricing" --graph ~/.graphify/global-graph.json | head
```

In Claude Code, confirm the statusline shows `dir (branch) model ctx:NN%`, and that
submitting a prompt inside a configured repo injects a `[graphify auto-consult …]` context
block (only after the global graph is built).

---

## Review workflow on the new PC

See **[REVIEWS.md](REVIEWS.md)** for the full convention. The short version:
- **Local Claude is your primary inline reviewer** — run `/code-review --comment` from your
  worktree before requesting merge. It posts inline on the PR diff at $0 GitHub-Actions cost.
- **Codex** runs as a gated Actions safety-net (only on *ready-for-review*, concurrency-cancelled).
- **Swap primary/fallback** when one hits limits, with one command (no file edits):
  ```bash
  gh variable set REVIEW_PRIMARY --body claude   # Codex rate-limited → rely on local Claude
  gh variable set REVIEW_PRIMARY --body codex    # Opus quota hit → re-enable Codex Actions
  ```
