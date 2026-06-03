# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.

## Graph-first protocol — MANDATORY for graphify-enabled work

Applies in any repo with a `graphify-out/` dir, and across the configured cross-repo
**GLOBAL** graph. Real connections are easy to miss, **especially across repos**. Consult
the graph BEFORE planning and BEFORE writing code — do not rely on grep/recall alone for
how things connect.

**GLOBAL graph (spans the configured repos):** `{{HOME}}/.graphify/global-graph.json`
(canonical path: `graphify global path`). Pass `--graph <GLOBAL>` for cross-repo answers;
omit it to query only the current repo's `graphify-out/graph.json`.

**WHEN (treat as non-optional):**
- Entering plan mode, or designing any non-trivial change.
- Before editing/creating code that touches a service, route, model, middleware, or shared util.
- Any time a change could ripple across repos, or touches auth, payments, vouchers, notifications, or fleet/cross-DB access.

**HOW:**
- Find concepts / where-is-this (fuzzy, best default): `graphify query "<concepts>" --graph <GLOBAL>`
- A node + its neighbors: `graphify explain "<node>" --graph <GLOBAL>`
- Blast radius before a change (needs an exact node label): `graphify affected "<node>" --graph <GLOBAL>`
- How two things connect: `graphify path "<A>" "<B>" --graph <GLOBAL>`
- The community map for a repo: read its `graphify-out/GRAPH_REPORT.md`.

**THEN:** fold the findings into the plan — name the connected nodes/files the graph surfaced,
and explicitly call out any cross-repo touch points before writing code. If the graph
contradicts an assumption from the brief or from memory, surface that rather than coding
past it. (This complements, does not replace, the project's "read before write / enumerate
sibling sites" rules.)

**Freshness:** per-repo graphs auto-refresh on every commit (free `post-commit` hook,
AST-only). The GLOBAL graph is a snapshot — it does NOT auto-update; re-extract occasionally
or after large changes: `graphify extract <repo-path> --backend claude --global --as <name>`
(costs API tokens, ~$3–6/repo). Requires `ANTHROPIC_API_KEY` in env + the `anthropic` SDK in
graphify's uv venv.
