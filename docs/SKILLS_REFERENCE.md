# Skills Reference

## Core Workflow

### `/letsbuild`
**Tier:** Minimal | **Purpose:** Multi-agent safe start

Creates an isolated git worktree, assigns a window ID, creates a feature branch, and registers work. Self-healing — cleans up stale state automatically.

**Usage:** Run at the start of every new task. Mandatory before any code changes.

### `/shipit`
**Tier:** Standard | **Purpose:** Deployment workflow

Commits changes, pushes feature branch, creates staging PR, optionally creates production PR. Includes conflict pre-check, changelog generation, and worktree cleanup.

**Usage:** When you're ready to deploy. Says "ship it" or invoke directly.

### `/feature`
**Tier:** Full | **Purpose:** Feature request management

Tracks feature requests in `docs/FEATURE_REQUESTS.md`. Add, review, or list requests.

**Usage:** `/feature add <description>`, `/feature review`, `/feature list`

---

## Review Skills

### `/code-review`
**Tier:** Standard | **Purpose:** Post-implementation code review

Generic quality/security/performance checklist + project-specific addon (`code-review-addons.md`). Can invoke the `code-reviewer` agent for deep analysis.

### `/security-review`
**Tier:** Full | **Purpose:** Security audit

OWASP Top 10 checklist + project-specific security profile (`security-review-addons.md`).

### `/api-review`
**Tier:** Full | **Purpose:** REST API design review

Evaluates RESTful design, pagination, status codes, auth, validation. Project-specific via `api-review-addons.md`.

### `/pre-deploy`
**Tier:** Standard | **Purpose:** Deployment readiness

10-section checklist: code quality, security, testing, database, API, config, performance, monitoring, docs, project-specific. Produces READY/NOT_READY verdict.

---

## Plan Review Skills

### `/plan-eng-review`
**Tier:** Standard | **Purpose:** Engineering architecture review

4-section review: architecture, code quality forecast, test coverage plan, performance & failure modes. Rates each 1-5 with specific findings.

### `/plan-design-review`
**Tier:** Full | **Purpose:** UX and design review

7-pass review: info architecture, states, user journey, AI slop detection, design system, responsive, key decisions. Rates each 0-10.

### `/plan-ceo-review`
**Tier:** Full | **Purpose:** Founder-mode strategy review

Challenges premises, applies 10-star framework, analyzes opportunity cost. Four modes: scope expansion, selective expansion, hold scope, scope reduction.

---

## Utility Skills

### `/retro`
**Tier:** Standard | **Purpose:** Weekly engineering retrospective

Analyzes git history for commit patterns, per-person contributions, hotspots, work sessions. Persists snapshots for trend tracking.

**Usage:** `/retro` (last 7 days) or `/retro 14d` (custom window)

### `/document-release`
**Tier:** Full | **Purpose:** Post-ship documentation sync

Audits README, ARCHITECTURE, CONTRIBUTING, CLAUDE.md against the diff. Polishes CHANGELOG, cleans up TODOs.

### `/token-audit`
**Tier:** Standard | **Purpose:** Context efficiency monitor

Measures token footprint of CLAUDE.md, memory, skills, agents, settings. Identifies waste, duplication, staleness.

### `/perf-test`
**Tier:** Full | **Purpose:** Performance benchmarks and load testing

Runs service-level benchmarks and HTTP load tests with configurable profiles (smoke, light, medium, stress).

### `/effort-optimizer`
**Tier:** Full | **Purpose:** Dynamic effort level recommendations

Classifies the current task and recommends optimal `/effort` level and `/model` for cost/quality balance.
