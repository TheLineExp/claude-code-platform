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

---

# Operating Rules — every window

These are the same in every window. They exist because rule-drift across files makes agent
behavior inconsistent window-to-window. If any per-repo CLAUDE.md, skill, or memory
contradicts these, THESE win — and fix the drifted copy.

1. **Graphify first** — consult the graph before planning or touching shared/cross-repo code
   (service/route/model/middleware/auth/payments/cross-DB). Not required for trivial
   single-file edits.
2. **Start work in an isolated worktree/branch before any code** — never commit to
   `staging`/`master`/`main` directly.
3. **Local code review BEFORE every push — always, automatic, no exceptions.** Run your
   review on `git diff <base>...HEAD` and FIX every finding before pushing. Goal: the PR
   opens clean, nothing left for CI to catch. Never "want me to review?", never "let CI
   catch it." This is the PRIMARY review gate.
4. **Every PR mention IS a verified link line.** Whenever a message names a PR, it renders as
   exactly this shape: `[<owner>/<repo>#<n>](https://github.com/<owner>/<repo>/pull/<n>) — <STATE> → <baseRef> (<action — e.g. "needs your merge">)`.
   Build STATE/baseRef from `gh pr view <n> --repo <owner>/<repo> --json state,baseRefName,url,mergedAt`
   run right before writing the line — from that live output, never from memory. A PR named
   without this full shape is incomplete output, not a style choice; the user never has to
   hunt for the link or its state.
5. **Each review comment gets one reply ON ITS OWN THREAD.** For every reviewer/bot comment,
   the response IS a reply posted to that comment's thread
   (`gh api repos/<owner>/<repo>/pulls/<n>/comments -F in_reply_to=<id> -f body="..."`)
   whose body states either the fix (file:line + SHA) or why it's a non-issue — then resolve
   the thread. The unit is one-thread-one-reply, landing inline on the diff where the
   reviewer reads it. A journal/chat/bottom-of-PR summary is the wrong location for that
   output, not a substitute for it.
6. **Agents never merge** — only the user merges any PR. Create PRs, report links.
7. **No worktree/branch cleanup until verified live in production.**

**Posture:** local review is the PRIMARY gate (rule 3, pre-push, $0 CI); a CI reviewer is a
safety-net, not a merge blocker. Keep small, discrete, one-concern PRs — this is what makes
review catch bugs. Risk-scope heavy ship checks (skip for one-line or backend-only fixes).
CI on the PR is the real diff-level gate.

**Form note — why rules 4 & 5 read as contracts, not prohibitions.** Match the form to the
failure (see the `writing-skills` skill). A rule that fails under *pressure* — you're tempted
to skip it under time/sunk-cost pressure — is stated as a prohibition plus a rebuttal of the
rationalization (rules 2, 3, 6). A rule where the *output comes out the wrong shape or place*
(rules 4, 5) is stated as a positive contract — what the output IS — because prohibitions
backfire on shaping problems while a recipe makes the right shape the default.
