# `/pm` — Project Manager Skill

Multi-window project orchestration for Claude Code. Turns the invoking window into the **M (manager)** — coordinating dev windows, routing chunks of a master plan, verifying merges, running cross-system milestone reviews, and shipping.

## Why this exists

Real cross-repo features hit a wall around two parallel windows. Three or more, and the seams break: file collisions, contradictory decisions, stale registries, lost context when a window crashes. This skill captures a working pattern from coordinating ~5 simultaneous Claude Code windows across 3 repos for a multi-week feature, and turns it into a reusable harness.

The PM has the **complete cross-system picture**. Each dev window sees its slice; the PM sees the whole. That's the source of every advantage:

- Better routing decisions (knows where collisions will happen before they do)
- Better milestone reviews (sees how chunks compose, not just individual diffs)
- Tighter integration testing (cross-repo invariants only the PM can check)
- Faster decision resolution (centralizes contradictions surfaced from any dev)

## Quick start

```bash
# 1. Initialize a project from a master plan file
/pm init my-project ~/.claude/plans/my-master-plan.md

# 2. The skill outputs the M-orchestrator prompt — paste it into this window's role.

# 3. Audit the current state of your repos
/pm sweep

# 4. Generate a brief for the first chunk and hand it to a new dev window
/pm brief P1
# Open a new Claude Code window, paste the brief, work begins

# 5. When dev reports back, verify and route
/pm verify 49           # confirms PR #49 merged on origin/staging
/pm route w1 P2         # generates handoff prompt for window w1's next chunk

# 6. At every track completion, run the cross-system review
/pm milestone track-P-complete

# 7. Mark a chunk shipped (refuses if acceptance + reviews aren't clean)
/pm ship P5 53

# 8. When the project is done, archive
/pm done
```

## Subcommands

See [`SKILL.md`](SKILL.md) for the full subcommand spec.

| Subcommand | Purpose |
|---|---|
| `init` | Set up artifacts dir from a master plan |
| `sweep` | Multi-repo audit (worktrees, dirty state, stale branches, open PRs) |
| `brief` | Generate dev brief from a chunk |
| `route` | Handoff prompt for next chunk |
| `verify` | Confirm PR merged on origin |
| `status` | Live roll-up |
| `roster` | Active windows with last-activity |
| `decisions open\|answer` | Decision-doc lifecycle |
| `blocked` | Structured blocker escalation |
| `ship` | Mark chunk done (acceptance + review gated) |
| `acceptance` | Per-chunk evidence review |
| `milestone` | Cross-system review chain |
| `review` | One-off review |
| `done` | Archive project |

## Architecture

### File layout
```
~/.claude/
├── skills/pm/                          # the skill itself
│   ├── SKILL.md
│   ├── README.md
│   ├── templates/
│   ├── scripts/
│   └── hooks/
└── pm/                                 # per-project artifacts
    ├── .active-project                 # which project is in focus
    ├── <project-name>/
    │   ├── master-plan.md
    │   ├── status.md
    │   ├── roster.md
    │   ├── roster-events.jsonl         # append-only event log
    │   ├── acceptance-log.md
    │   ├── briefs/
    │   ├── decisions/
    │   ├── reports/
    │   └── reviews/                    # milestone review outputs
    └── archive/
        └── <project>-<date>/
```

### Key design choices

**1. Append-only roster.** Active-work.md edits race when multiple windows update simultaneously (we hit this twice in the inspiration session). Instead, every event is a JSONL line; `roster.md` is regenerated on demand.

**2. Cross-repo persistence.** Project state lives in `~/.claude/pm/`, not in any product repo. Survives repo cleanups, branch deletes, window crashes. Loses the "reviewable in PRs" property — accepted tradeoff.

**3. PM never writes feature code.** The skill enforces this in its standing prompt. Discipline is the thing that keeps parallel windows productive.

**4. Reviews block ships.** `/pm ship` refuses to mark a chunk done if the latest milestone review has unresolved critical findings. Override with `--force` (logged).

**5. Skill chaining.** `/pm milestone` calls `code-reviewer`, `security-review`, `api-review`, `gstack-review`, `deploy-verifier`, and tests as a single chain. The PM's cross-system context goes into each agent's prompt — every reviewer knows the whole.

## Milestone review chain

The cross-system review at every track completion. Sequence:

1. **Diff aggregation** — collect every PR in the milestone across all repos
2. **code-reviewer** — cross-repo code quality, with file-ownership matrix as input
3. **security-review** — auth, PII, encryption, JWT pinning
4. **api-review** — REST design on new endpoints
5. **gstack-review** — SQL safety on every migration
6. **Test suites** — `npm test` in each affected repo
7. **Coverage delta** — flag regressions
8. **Findings classification** — critical / warning / info
9. **Block-ship gate** — any critical finding blocks `/pm ship`

Run with `--full` to add `deploy-verifier` and `realworld-user` for E2E.

## Hooks (optional)

Two reference hooks ship with the skill. Install in any product repo's `.git/hooks/`:

| Hook | Purpose |
|---|---|
| `pre-commit-roster.sh` | Validates `.claude/active-work.md` format on commit; rejects duplicate window IDs |
| `post-merge-status.sh` | Called by GH Actions on staging push; appends a `chunk-merged` event to the active project |

## Integration with existing skills

| When | Calls |
|---|---|
| `/pm sweep` | optionally `env-audit` |
| `/pm milestone` | `code-reviewer`, `security-review`, `api-review`, `gstack-review` |
| `/pm milestone --full` | + `deploy-verifier`, `realworld-user` |
| `/pm ship` (final chunk in a track) | suggests `shipit` |
| `/pm review` (one-off) | `code-reviewer` + selective specialists |

## When NOT to use

- Single-repo, single-developer task — overhead isn't worth it
- One-off bug fix or hotfix — use `letsbuild` + `shipit` directly
- Exploration with no defined chunks — use `Plan` mode

The PM pattern is for: multi-repo features, parallel workstreams, week-plus timelines, cross-system coordination as the actual hard part.

## Provenance

Distilled from a real session coordinating 5 windows across `fleetmanager-vouchers`, `fleetmanager-reservations`, and `Fleetmanager_V3` for the VoloPass production roadmap (the `enchanted-riding-pnueli.md` plan, Apr 2026). The pattern that worked is the pattern this skill encodes.

## License

Personal config — copy and adapt freely.
