# Claude Code Development Platform

A battle-tested, distributable development environment for Claude Code + VS Code. Provides multi-agent safety, automated code review, deployment workflows, context conservation, and self-healing error handling — out of the box.

Born from production use across 3 repos and hundreds of development sessions. Packaged for any team to adopt and customize.

## What You Get

### Safety Rails (9 hooks)
- **Branch protection** — blocks commits to staging/main/master
- **Worktree enforcement** — agents work in isolated directories, can't overwrite each other
- **Destructive operation blocking** — no force push, hard reset, or checkout .
- **PR merge prevention** — agents create PRs, only humans merge
- **Work registration** — every agent registers their branch before committing
- **Secrets detection** — blocks commits containing .env, credentials, keys
- **File redirect blocking** — closes the `echo > file` worktree bypass
- **Interactive mode blocking** — prevents `git rebase -i` (no TTY in Claude Code)

### Skills (15)
| Skill | Purpose |
|-------|---------|
| `/letsbuild` | Create isolated worktree, assign window ID, register work |
| `/shipit` | Commit, push, create staging + production PRs |
| `/code-review` | Post-implementation code review with addon support |
| `/security-review` | OWASP-based security audit |
| `/api-review` | REST API design review |
| `/pre-deploy` | 10-section deployment readiness check |
| `/plan-eng-review` | Architecture and engineering plan review |
| `/plan-design-review` | UX and design plan review |
| `/plan-ceo-review` | Founder-mode scope and strategy review |
| `/retro` | Weekly engineering retrospective from git history |
| `/document-release` | Post-ship documentation sync |
| `/token-audit` | Context efficiency analysis |
| `/perf-test` | Performance benchmarks and load testing |
| `/feature` | Feature request backlog management |
| `/effort-optimizer` | Task-based effort level and model recommendations |

### Agents (4)
| Agent | Model | Purpose |
|-------|-------|---------|
| `code-reviewer` | Opus | Deep code review with project-specific addons |
| `deploy-verifier` | Sonnet | Post-deployment health checks |
| `perf-tester` | Sonnet | Performance benchmarks and load testing |
| `error-fixer` | Sonnet | Self-healing config error diagnosis (one-try rule) |

### Smart Features
- **Context conservation** — tracks tool calls, warns at 50/80/120, suggests new windows
- **Compaction protection** — injects critical rules before context compression
- **Self-healing errors** — detects config errors, attempts one fix, escalates on failure
- **Dynamic effort** — recommends `/effort` and `/model` based on task complexity
- **Permission presets** — cautious, standard, power-user (reduces approval friction)
- **Addon pattern** — project-specific checks without modifying platform files

## Quick Start

### Single repo (per-repo wizard)

```bash
# 1. Clone or use as template
git clone https://github.com/TheLineExp/claude-code-platform.git
cd claude-code-platform

# 2. Run the setup wizard
bash setup.sh

# 3. Open Claude Code
# The wizard generates CLAUDE.md, settings.json, and platform.config.json

# 4. Start your first feature
/letsbuild
```

The wizard asks for your project name, branches, test command, deployment URLs, and feature tier — then generates everything.

### Full machine (new PC) — user-global config + every repo

When you're standing up a **fresh machine**, the per-repo wizard isn't enough — it doesn't
reproduce your user-global `~/.claude` / `~/.codex` / `~/.graphify` config. Two extra scripts
handle that:

```bash
bash setup-machine.sh     # user-global: ~/.claude settings/skills/hooks/statusline, ~/.codex, graphify
bash setup-repos.sh       # clone + git hooks + .env scaffold for every repo in repos.json
```

`setup-machine.sh` de-hardcodes all machine paths (substitutes your real `HOME`/repos root),
so the committed templates stay portable. Edit **`repos.json`** to point the whole thing at
any set of repos. Full step-by-step: **[docs/NEW_PC.md](docs/NEW_PC.md)**.

## Feature Tiers

| Tier | Hooks | Skills | Agents | Best For |
|------|-------|--------|--------|----------|
| **Minimal** | All 9 | `/letsbuild` only | None | Solo developers wanting safety rails |
| **Standard** | All 9 | 7 core skills | `code-reviewer` | Most teams (recommended) |
| **Full** | All 9 | All 15 skills | All 4 agents | Teams wanting the complete platform |

## Permission Presets

| Preset | Auto-Approves | Best For |
|--------|--------------|----------|
| **Cautious** | Reads only | New users, sensitive codebases |
| **Standard** | Reads, edits, common git/npm/docker | Most developers (recommended) |
| **Power User** | Almost everything (hooks are safety net) | Experienced users who want speed |

## Architecture

```
Your Repo/
├── platform.config.json          # Central config (branches, test cmd, URLs)
├── CLAUDE.md                     # Project rules (generated from template)
├── .claude/
│   ├── settings.json             # Permissions + hook bindings
│   ├── settings.local.json       # Personal overrides (gitignored)
│   ├── window-id                 # "setup" in main repo, "w1"/"w2" in worktrees
│   ├── active-work.md            # Agent work registry
│   ├── hooks/                    # 12 hook scripts
│   │   ├── _config.sh            # Shared config loader (reads platform.config.json)
│   │   ├── _parse-input.sh       # Shared JSON parser + fast-path optimization
│   │   ├── block-*.sh            # Safety hooks (5)
│   │   ├── check-*.sh            # Validation hooks (2)
│   │   ├── enforce-worktree.sh   # Worktree isolation
│   │   ├── session-tracker.sh    # Context conservation
│   │   ├── compact-notifier.sh   # Compaction protection
│   │   └── error-handler.sh      # Self-healing errors
│   ├── skills/                   # 15 skill definitions
│   └── agents/                   # 4 agent definitions
├── hooks/                        # Git hooks
│   ├── pre-commit                # Branch protection + secrets + tests
│   ├── pre-push                  # Production branch protection
│   ├── install.sh                # Hook installer
│   └── verify.sh                 # Drift detection
└── docs/                         # Documentation
```

### How It Works

1. **Hooks** run on every tool call via `settings.json` bindings
2. **Permissions** auto-approve safe operations, deny dangerous ones
3. **Skills** provide structured workflows invoked with `/skillname`
4. **Agents** handle complex tasks (code review, deployment verification)
5. **Config** (`platform.config.json`) centralizes project settings — hooks read it at runtime
6. **Addons** (`*-addons.md` files) inject project-specific checks without modifying platform files

## Customization

### Project-Specific Checks (Addon Pattern)

Create addon files to extend platform skills:

```markdown
<!-- .claude/code-review-addons.md -->
## Security (Critical)
- [ ] All PII encrypted with encryptionService
- [ ] Searchable fields have HMAC hashes

## Framework
- [ ] Business logic in services (not routes)
- [ ] Use asyncHandler wrapper on all Express routes
```

Skills automatically read their addon file if it exists.

### Available Addon Files

| File | Extends |
|------|---------|
| `.claude/code-review-addons.md` | `/code-review` + `code-reviewer` agent |
| `.claude/security-review-addons.md` | `/security-review` |
| `.claude/api-review-addons.md` | `/api-review` |
| `.claude/pre-deploy-addons.md` | `/pre-deploy` |
| `.claude/perf-test-addons.md` | `/perf-test` |
| `.claude/deploy-verifier-addons.md` | `deploy-verifier` agent |

See [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md) for detailed customization guide.

## Documentation

- [NEW_PC.md](docs/NEW_PC.md) — **Full-machine bootstrap** (new computer, start to finish)
- [REVIEWS.md](docs/REVIEWS.md) — PR review convention (local Claude + gated Codex, primary/fallback swap)
- [SETUP.md](docs/SETUP.md) — Detailed setup for each OS
- [CUSTOMIZATION.md](docs/CUSTOMIZATION.md) — How to add addons, skills, agents
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — How the platform works internally
- [SKILLS_REFERENCE.md](docs/SKILLS_REFERENCE.md) — Every skill with usage examples
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — Common issues and fixes

## Examples

Pre-built configurations for common tech stacks:

- [Node.js / Express](examples/node-express/)
- [Python / Django](examples/python-django/)
- [React Frontend](examples/react-frontend/)
- [FleetManager](examples/fleetmanager/) — The original production config

## License

MIT
