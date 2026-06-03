---
name: route
description: Quota-aware task routing. Delegates mechanical / low-judgment work (bulk edits, mechanical refactors, log scraping, file reads + summary, test runs, grep/glob sweeps, doc updates from a known spec) to a Sonnet subagent via the Agent tool with `model: "sonnet"`, while keeping high-judgment work (architecture, design, debugging unknowns, review, planning, scoping, novel code) on the main Opus thread. Use to stretch Opus weekly quota without giving up Opus on the hard parts. Triggers — "use route", "/route", "route this", "delegate to sonnet", or invoke proactively at the start of any task that fits the mechanical profile.
---

# Route — Quota-Aware Task Routing

You are the **main Opus thread**. This skill teaches you when to delegate work to a Sonnet subagent so that Opus quota gets spent on judgment, not typing.

The lever is real: `Agent` tool calls accept a `model` parameter. Setting `model: "sonnet"` runs that subtask on Sonnet 4.6 regardless of the main session's model. Quota for that subagent comes out of the Sonnet bucket, not Opus.

This skill does NOT switch the main session's model — that requires the user to run `/model`. It routes *subtasks* only.

---

## The routing rule

For every non-trivial task the user gives you, classify it before acting:

### Delegate to Sonnet (cheap bucket)

Dispatch via `Agent(model: "sonnet", ...)` when the task is:

- **Mechanical edits** — rename a symbol across N files, apply a known pattern, swap an import path, update a version string, normalize formatting.
- **Bulk reads + summary** — "what does this folder do", "summarize these 5 files", "find all callers of X and list them".
- **Search / grep sweeps** — locating definitions, references, usages, dead code candidates. (The `Explore` subagent already does this; use it.)
- **Test execution + parsing** — run `npm test`, parse the failure list, report which tests failed and why. Not *fixing* the failures — just reporting.
- **Log scraping** — pull container logs, filter for errors, summarize.
- **Doc updates from a known spec** — "update README to mention the new endpoint we just added at /foo".
- **Status gathering** — `git status`, `gh pr list`, `gh run list`, health checks, env audits where the output format is known.
- **Mechanical PR-body / commit-message drafting** when the diff is small and uncontroversial.

### Keep on Opus (main thread)

Do NOT delegate when the task involves:

- **Architecture or design decisions** — new abstractions, trade-off calls, schema design, API shape.
- **Debugging unknown failures** — root-cause analysis, novel bugs, anything where the path forward isn't obvious.
- **Code review** — `/gstack-review`, `/code-review`, `/security-review`, PR audits. Judgment-heavy by definition.
- **Planning / scoping** — breaking down work, sequencing, identifying risks.
- **Novel code writing** — anything where the right shape isn't already obvious from the codebase.
- **PM orchestration** — M-window work (briefs, routing, milestone reviews) stays on Opus. The whole point of M is judgment.
- **User-facing strategic conversations** — the conversation you're having right now.

### Ambiguous? Default to Opus.

If you can't decide in 5 seconds which bucket a task falls in, it's a judgment task. Keep it on Opus. False-positive delegation (Sonnet flubs a subtle call) costs more than false-negative (Opus does a mechanical edit) — you re-do the work AND lose the Opus tokens you would have spent anyway.

---

## How to delegate

Use the standard `Agent` tool with two non-default parameters:

```
Agent({
  description: "<3-5 word task>",
  subagent_type: "general-purpose",   // or "Explore" for search-only
  model: "sonnet",                     // <-- the lever
  prompt: "<self-contained brief>"
})
```

The prompt must be **fully self-contained** — the subagent sees none of your conversation. Spell out: the goal, the files/paths involved, the exact change to make, any constraints (no new abstractions, match existing style, don't touch X), and the output you want back (a short report, the file diff, a list).

**Brief the subagent like a new colleague.** Terse command-style prompts produce shallow generic work — same rule as any Agent call.

For tasks that fit a specialized agent (`Explore`, `code-reviewer`, `Plan`), use that `subagent_type` and still pass `model: "sonnet"` to route it cheaply. Exception: `code-reviewer`, `Plan`, and `plan-*-review` agents are judgment-heavy — leave them on their default model.

---

## Interaction with PM skill

The PM skill's M-window orchestration stays on Opus — briefs, routing decisions, milestone reviews, verification all require judgment. Dev-window work is already in a separate window with its own model setting, so this skill doesn't apply there.

Where `route` *does* help an M window:

- **`/pm sweep`** mechanics — running `git log`, `gh pr list`, parsing PR states across repos. Delegate the data-gathering pass to Sonnet, do the routing decisions on Opus.
- **Codex post-merge sweeps** — fetching `gh api .../comments` across recent PRs and surfacing findings is mechanical; deciding which findings are real bugs is judgment.
- **`/pm acceptance` / `/pm verify`** — confirming a PR merged, the deploy went green, the health endpoint reports OK. Pure mechanical lookup.

---

## What this skill does NOT do

- **Does not switch the main session's model.** `/model` is user-driven. If the user wants the main thread on Sonnet, they run `/model` themselves.
- **Does not route to skills.** `/shipit`, `/letsbuild`, `/pre-deploy` are skills invoked on the main thread; they run on whatever model the main session is set to. If the user wants those on Sonnet, they switch the main session before invoking them. (Tell them this when relevant — see the nudge pattern below.)
- **Does not change which agent definitions are eligible** — agents with a pinned `model:` in their frontmatter ignore the override unless you explicitly pass `model:`.

### Nudge pattern for skill-based workflows

When the user says "ship it" / "/shipit" / "/letsbuild" / "/pre-deploy" and you're aware they're managing Opus quota, prefix your response with one line:

> Heads-up: this runs on the main thread's model. If you want it on Sonnet to save Opus quota, run `/model` → Sonnet first, then re-invoke. Otherwise I'll proceed on the current model.

Do not block on confirmation — proceed if they don't redirect. Mention it once per session, not every time.

---

## Quick reference

| Task | Route to | Why |
|------|----------|-----|
| "Rename `foo` to `bar` across the backend" | Sonnet (Agent) | Mechanical |
| "Find every caller of `assertFleetAccess`" | Sonnet (Explore) | Search |
| "Why is this test failing intermittently?" | Opus (main) | Debugging unknown |
| "Run the test suite and tell me what failed" | Sonnet (Agent) | Mechanical |
| "Design the schema for the new offerings table" | Opus (main) | Design judgment |
| "Update the README to reflect the new env var" | Sonnet (Agent) | Spec-driven doc edit |
| "Review this PR" | Opus (code-reviewer) | Judgment-heavy review |
| "Pull the last 50 lines of the staging API logs" | Sonnet (Agent) | Log scraping |
| "Plan the rollout for the migration" | Opus (Plan) | Planning |
| "Apply the per-bike multiplier fix I just described to the other two call sites" | Sonnet (Agent) | Mechanical replication of a known fix |

---

## End-of-session note

If the user is approaching their Opus weekly limit, surface it once: "You've been on Opus for a while — this next task looks mechanical, I'll send it to Sonnet via Agent. Want me to keep auto-routing for the rest of the session?" If they say yes, stay aggressive on delegation for the remainder. If they say no, fall back to default behavior.
