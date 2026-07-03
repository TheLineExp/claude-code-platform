# Skills & Agents Reference

Canonical source: `platform/global/skills/*/SKILL.md` and `platform/global/agents/*.md`.
This page summarizes; the SKILL.md files are authoritative. Everything here is user-global
(synced to `~/.claude` by `setup-machine.sh`) — there are no per-repo skills or agents.

## Skills (9)

### `/doctrine`
The Operating Doctrine — five non-negotiable engineering rules (do the work / root-cause
not patch / detect spinning / no unilateral backlog / no surprise features) plus the gates
that enforce them: the PLANNING gate before any code, the SHIP backstop before deploying,
the ZOOM-OUT protocol when spinning, and an AUDIT mode for plans/diffs/sessions.
Auto-referenced by letsbuild (plan gate), shipit (ship backstop), and pm (M-window rules).

### `/letsbuild`
Safe feature-start workflow. Creates an isolated git worktree, assigns a window ID, creates
the feature branch, and registers the work — mandatory before starting anything, so
parallel agent windows can't overwrite each other. Self-healing: cleans up stale state from
previous sessions. Runs the doctrine plan-gate at Phase 0.

### `/shipit`
Ship workflow: commit, push, staging PR → production PR. Gates on the way out:
`parity-sweep` + `money-concurrency-reviewer` agent passes, the doctrine ship backstop, the
**PR-Ready gate** (checks green + zero unresolved review threads before any "ready" claim),
and the **prod-promotion gate** (staging must be converged first). Rotates the session
after shipping.

### `/code-review` *(built-in)*
Claude Code's built-in diff review — the review pathway, paired with the three agents
below for money/state/cross-layer changes.

### `/route`
Quota-aware task routing. Delegates mechanical, low-judgment work (bulk edits, grep
sweeps, file reads + summary, test runs, doc updates from a known spec) to a Sonnet
subagent, keeping high-judgment work (architecture, debugging, review, planning, novel
code) on the main Opus thread. Invoked proactively, not just on `/route`.

### `/graphify`
Any input (code, docs, papers) → knowledge graph, plus query/explain/affected/path
commands over it. Used on demand for codebase questions; graph-first before planning or
editing shared/cross-repo code. (The old auto-consult prompt hook is retired.)

### `/pm`
Multi-window project orchestration. The invoking window becomes the manager — routing
chunks of a master plan to dev windows, verifying merges, running cross-system milestone
reviews. Subcommands: `init`, `sweep`, `brief`, `route`, `verify`, `status`, `roster`,
`decisions`, `blocked`, `ship`, `acceptance`, `milestone`, `review`, `done`.

### `/todo`
Cross-repo QUALITY-SWEEP backlog for SMALL, well-defined fixes/tweaks/ops across the fleet
repos. Persistent, file-backed (`backlog/TODO.md` in this repo), cross-machine. Every add
is confirmed by the `backlog-gate` hook (Doctrine Rule 4 — no unilateral backlog).

### `/feature`
Cross-repo backlog for LARGE, undefined feature projects (net-new capabilities or
redesigns needing scoping/design, typically multi-PR) across the fleet repos. File-backed
(`backlog/FEATURES.md`). Also gated by `backlog-gate`. Distinct from `/todo` (small,
well-defined) and per-repo MASTER_PLAN.md (phase tracking).

### `/traceability-review`
End-to-end call-chain verification: traces every button, link, and form action through
UI → API client → backend route → service → database, verifying function signatures,
argument passing, and return shapes match at every boundary. Use after multi-layer
features and before deploying. Backed by the `traceability-reviewer` agent.

## Agents (3) — `platform/global/agents/`

### `parity-sweep`
Blast-radius parity sweeper. Given a branch/diff touching payments/refunds/vouchers, state
transitions, shared helpers/serializers, auth gates, config surfaces, or concurrency, it
enumerates every sibling call site, twin surface, config surface, and legacy-data
implication and verifies each is consistent with the change. Read-only; returns PASS/BLOCK.
Exists because ~65% of external-reviewer P1/P2s were locally-correct changes whose sibling
surface was missed (see the audit). Run before every ship and after every review-fix round.

### `money-concurrency-reviewer`
Adversarial money-path and concurrency reviewer. Run on the FINAL HEAD of any change
touching payments, refunds, settlements, vouchers, Stripe/webhooks, balances, idempotency,
locks, or state machines — before push AND again after every review-fix round (fixes
introduce new bugs). Reads whole call chains, never snippets; returns verified P1/P2
findings with exact interleavings. Exists because ~40% of P1s were TOCTOU/stale-snapshot.

### `traceability-reviewer`
End-to-end call-chain checker across the FleetManager + Reservations stack (the engine
behind `/traceability-review`). Verifies signatures, argument names/types, and return
shapes at every layer boundary after cross-layer features or API-client/route refactors.

## Retired — do not reference

- `gstack-ship`, `gstack-review` (replaced by `/shipit` + `/code-review` + agents)
- `graphify-autoquery.js` prompt hook (junk graph-node injection)
- The old per-repo skill/agent copies and the old agents
  (code-reviewer / perf-tester / error-fixer / deploy-verifier)
