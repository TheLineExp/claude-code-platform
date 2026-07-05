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
Safe feature-start workflow, mandatory before starting anything. Runs the doctrine
plan-gate at Phase 0, then the **`project-evaluator` agent at Phase 0.5** — every project
gets a fresh-context plan check + sizing verdict: SOLO continues here; ≥3-PR (or 2-PR
long-context) projects divert to `/pm` by default. Then creates an isolated git worktree,
assigns a window ID, creates the feature branch, and registers the work so parallel agent
windows can't overwrite each other. Self-healing: cleans up stale state from previous
sessions.

### `/shipit`
Ship workflow: commit, push, staging PR → production PR. Gates on the way out:
`parity-sweep` + `money-concurrency-reviewer` agent passes, the doctrine ship backstop, the
**outside-lens review (Step 4b — `outside-reviewer` agent, every ship, after commit before
push, re-run on every fix round)**, the **PR-Ready gate** (checks green + zero unresolved
review threads before any "ready" claim), and the **prod-promotion gate** (staging must be
converged first). Rotates the session after shipping.

### `/code-review` *(built-in)*
Claude Code's built-in diff review — the review pathway, paired with the agents
below for money/state/cross-layer changes and the every-ship outside-lens round.

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
reviews. **DEFAULT route for ≥3-PR (or 2-PR long-context) projects, entered automatically
via letsbuild Phase 0.5**; M holds continuity at low context, dev windows manage the
details. Subcommands: `init`, `sweep`, `brief`, `route`, `verify`, `status`, `roster`,
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

## Agents (5) — `platform/global/agents/`

> This heading is the ONE canonical agent count/roster. Other docs (README, ARCHITECTURE,
> SETUP, NEW_PC) link here instead of restating the number — hand-duplicated counts drifted
> across 7 files the last time an agent was added.

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

### `project-evaluator`
Post-planning sizing gate — runs MANDATORY on every project at letsbuild Phase 0.5,
between plan acceptance and build start. Fresh-context (it didn't write the plan): plan
check (gaps/risks) + sizing verdict. Routes SOLO (1–2 PRs, fits one window → letsbuild
continues) or PM (≥3 PRs, or 2 PRs long-context/multi-repo → `/pm` orchestration by
DEFAULT, with a proposed chunk table that seeds the master plan).

### `outside-reviewer`
Context-isolated adversarial pre-push reviewer — the local stand-in for the external
(Codex) round, run MANDATORY on every ship at shipit Step 4b and on every fix round before
pushing it. Sees ONLY what an external reviewer sees (diff + changed files + PR
description), none of the authoring session's reasoning, and hunts the 7-family Codex
catch taxonomy. Goal: Codex converges in ≤1 round instead of 4–8.

## Retired — do not reference

- `gstack-ship`, `gstack-review` (replaced by `/shipit` + `/code-review` + agents)
- `graphify-autoquery.js` prompt hook (junk graph-node injection)
- The old per-repo skill/agent copies and the old agents
  (code-reviewer / perf-tester / error-fixer / deploy-verifier)
