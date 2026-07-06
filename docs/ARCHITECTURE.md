# Architecture

How the dev system is layered, why it's shaped this way, and where each piece lives.
Background: [AUDIT-2026-07-02.md](AUDIT-2026-07-02.md) — two weeks of failure data showed the
old design (per-repo skill copies, gstack, graphify prompt injection) caused drift and junk
context; the fix was one canonical layer with a single sync path.

## The two layers

```
claude-code-platform/platform/global/     CANONICAL — edited in git, reviewed, versioned
        │
        │  ./setup-machine.sh   (the ONLY writer of ~/.claude)
        ▼
~/.claude/                                GENERATED — never hand-edited
        skills/  agents/  hooks/backlog-gate.js  statusline-command.sh
        CLAUDE.md  settings.json          (rendered from templates)

fleet repos (.claude/ in each)            PER-REPO — guard hooks ONLY
        hooks/block-*.sh, enforce-worktree.sh, ...  + settings wiring
```

**Layer 1 — user-global (`platform/global/` → `~/.claude`).** All skills, agents, the
backlog-gate hook, statusline, and the two templates. Machine-specific paths are substituted
at sync time, so the committed templates stay portable.

**Layer 2 — per-repo (fleet repos).** Only guard hook scripts (`block-protected-branch`,
`block-destructive-git`, `enforce-worktree`, etc.) and the `settings.json` wiring that binds
them. **No per-repo skills or agents.** They previously existed and drifted into three
divergent copies — the audit's core finding — so they were deleted; behavior now comes from
the global layer only.

## Canonical layer contents

### Skills — `platform/global/skills/`

doctrine, feature, graphify, letsbuild, pm, route, shipit, todo, traceability-review.
Full descriptions: [SKILLS_REFERENCE.md](SKILLS_REFERENCE.md).

### Agents — `platform/global/agents/`

(Canonical roster + count live in [SKILLS_REFERENCE.md](SKILLS_REFERENCE.md) — don't restate the number here.)

| Agent | Role |
|-------|------|
| `parity-sweep` | Blast-radius sweeper: finds the sibling call site / twin route / parallel serializer / config surface the diff did NOT change but made inconsistent |
| `money-concurrency-reviewer` | Adversarial TOCTOU/race reviewer for money paths (payments, refunds, vouchers, webhooks, locks, state machines) |
| `traceability-reviewer` | End-to-end call-chain checker: UI → API client → route → service → DB, verifying signatures and shapes at every boundary |
| `project-evaluator` | Post-planning sizing gate (letsbuild Phase 0.5): fresh-context plan check + SOLO-vs-PM routing verdict with a proposed chunk table |
| `outside-reviewer` | Context-isolated pre-push reviewer (shipit Step 4b, every ship): sees only diff + spec, hunts the Codex catch taxonomy — the local external-lens round |

### Hooks and support files

- `backlog-gate.js` — PreToolUse(Skill) hook; confirm-prompts every `/todo` and `/feature`
  add so a model-initiated backlog entry can't pass silently (Doctrine Rule 4). Fails open.
- `session-guard.js` — UserPromptSubmit hook; recommends a fresh session when the current
  one grows long.
- `check-fix-landed.sh` — PostToolUse(Bash) ADVISORY (never blocks): after a `git commit` /
  `git push`, checks the branch's PR and loudly flags an ORPHANED fix — pushed to a branch
  whose PR is already merged/closed, or a branch with no PR — so a fix can't silently miss
  deploy. Confirms the benign case (`✓ on open PR #N`) and, for a merged PR, verifies the
  merge actually included the commit. Reuses `_tokenize.pl` to resolve the git action + cwd.
- `statusline-command.sh` — statusline (`dir (branch) model ctx:NN%`).
- `claude-CLAUDE.template.md` / `claude-settings.template.json` — plain-copied to
  `~/.claude/CLAUDE.md` and `~/.claude/settings.json` (no substitution).
- `graphify-autoquery.js` — **retired from deployment**. Kept in the repo for reference; its
  entity extraction injected junk graph nodes into every prompt. `/graphify` remains a
  normal on-demand skill.

## Deployment model

`setup-machine.sh` is the single writer of `~/.claude`:

- **Default mode** — syncs `platform/global/` into `~/.claude`, backing up anything it
  overwrites to `~/.claude/backups/<timestamp>/`. It mirrors: the CLAUDE.md + settings.json
  templates (plain copy, no substitution); the skills and agents; the guard hooks —
  every `*.sh` **and** `_tokenize.pl` (the shared tokenizer every guard sources; a `*.sh`-only
  mirror would leave the guards fail-open); the `backlog-gate.js` + `session-guard.js` hooks
  and `statusline-command.sh`; and a `~/.claude/backlog-location` pointer to this repo's
  `backlog/` dir.
- **`--diff` mode** — read-only drift report (IDENTICAL / DIFFERS / MISSING / STRAY); exits
  1 on drift. Run before committing.

Change flow: edit `platform/global/` → `./setup-machine.sh` → commit. Never the other
direction. If `--diff` shows drift you didn't author here, someone hand-edited `~/.claude`;
port it into `platform/global/` if wanted, then re-sync.

## Workflow pathways — exactly one per task

| Phase | Pathway | Gates |
|-------|---------|-------|
| Start | `/letsbuild` | **doctrine plan-gate** at Phase 0; **project-evaluator agent** at Phase 0.5 sizes EVERY project — SOLO continues here; ≥3-PR (or 2-PR long-context) diverts to `/pm` by DEFAULT (this window = M at low context, dev windows execute chunks); then worktree + branch + registration |
| Orchestrate | `/pm` (auto-entered from letsbuild Phase 0.5, or manual) | Master plan → chunk briefs → dev windows (each runs `/letsbuild` + `/shipit`); M verifies merges, runs milestone reviews, keeps context low (context-discipline rules in the M prompt) |
| Ship | `/shipit` | Staging PR → prod PR. `parity-sweep` + `money-concurrency-reviewer` agent passes; doctrine ship backstop; **outside-lens review (Step 4b, every ship)** — context-isolated `outside-reviewer` agent must PASS before push, re-run on every fix round; **PR-Ready gate** — checks green + 0 unresolved review threads before any "ready" claim; **prod-promotion gate** — staging must be converged first; session rotation after ship |
| Review | built-in `/code-review` + the agents | — |
| Backlog | `/todo` (small) / `/feature` (large) | `backlog-gate` hook confirms every add |

Retired pathways: `gstack-ship`, `gstack-review`.

## Environment facts

- Single machine: Mike's Mac (darwin). No Windows, no Linux, no other users.
- Repos root: `/Users/mikekunz/Documents/Volo Technologies/` — the path contains a
  **space**; always quote it. Space-free symlink: `~/vt`.
- Repos: `fleetmanager-reservations` (prod `master`), `Fleetmanager_V3` (prod `main`),
  `fleetmanager-vouchers` (prod `master`), `claude-code-platform` (this repo).
  There is **no azure-ops repo**.
- Cross-repo backlog store: `backlog/` in this repo, located at runtime via
  `~/.claude/backlog-location` (written by `setup-machine.sh`).
