---
name: deep-audit
description: Deliberate, budgeted, multi-agent DEEP AUDIT of a target subsystem — the opt-in "super reviewer". Fans out broad-context finders (money/concurrency, parity, trust, legacy-data, error-paths, root-cause families), loops until dry, adversarially verifies each finding with a skeptic panel, and returns a ranked P1/P2 list plus a completeness note. This is the ON-DEMAND heavy mode — the OPPOSITE of the cheap diff-scoped ship review. Use when the user says "/deep-audit", "super review", "deep audit", "hunt for latent bugs in X", "audit the <subsystem>", "find the root cause across <area>", or wants a thorough issue-finding pass on a subsystem/incident/bug-family. NEVER auto-runs; only when explicitly invoked.
---

# Deep Audit — the opt-in super reviewer

The heavyweight, broad-context multi-agent review — packaged as a **deliberate tool you aim**,
not an automatic gate. It exists because that mode is genuinely effective at surfacing latent
bugs a diff-scoped review never sees; the only thing that made it a cost problem was running it
automatically and unscoped. Here it is explicit, targeted, and budgeted.

## HARD INVARIANTS (do not violate)
1. **Never automatic.** This runs ONLY when the user explicitly invokes it. NEVER wire it into
   `/shipit`, `/letsbuild`, a hook, or any auto-trigger. The cheap diff-scoped review stays the
   ship default (see CLAUDE.md "Review agents"). Re-introducing auto-runs rebuilds the cost bomb.
2. **Always targeted.** It hunts a TARGET the user names (a subsystem/path, a bug family, an
   incident, a root-cause question) — never "the whole codebase" blindly. If the user didn't
   give a target, ask for one before launching.
3. **Always budgeted + honest.** It caps spend and REPORTS what it capped/deferred — never
   silently truncates. Encourage the user to pass a budget (e.g. `+300k`) on invocation.

## How to run it

1. **Parse the invocation.** From the user's message extract:
   - `target` — the subsystem / path / bug-family / incident / question (required; ask if missing).
   - budget — if the user wrote a `+Nk` directive, the harness sets `budget.total` and the
     workflow honors it automatically. If they didn't, say so and suggest one; you may still run.
   - optional `maxRounds` / `maxVerify` overrides for depth.

2. **Echo the plan in one line, then launch** (invoking IS the opt-in — don't re-confirm at
   length). E.g. "Deep-auditing `<target>` across 6 lenses, loop-until-dry, budget ~300k — launching."

3. **Launch the Workflow** (this skill's instruction to call Workflow is itself the required
   opt-in for the Workflow tool):

   ```
   Workflow({
     scriptPath: "/Users/mikekunz/.claude/skills/deep-audit/audit-workflow.js",
     args: { target: "<the target>", repos: "<optional repo hint>", maxRounds: 6, maxVerify: 50 }
   })
   ```

   It runs in the background (fan-out is large); you'll be notified on completion. Do NOT
   re-implement the fan-out inline — the script is the engine.

4. **Relay the result** (the workflow returns a structured object) in Mike's report format —
   recap + numbered next steps:
   - Lead: what was audited and the headline (e.g. "3 confirmed P1, 5 P2 in the settlement money paths").
   - **In-target findings** ranked P1→P3: each with `file:line`, the failing scenario, and the
     shared `fixLocus` when it's a family (fix the resolver, not the call site — doctrine rule 2).
   - **"Real but outside the target"** findings in a separate bucket — surfaced, labeled, not noise.
   - The **completeness note** (what the audit likely missed) and whether it **hit the round/verify
     cap** (more may remain — offer a re-run to continue).
   - Budget spent.
   - Numbered next steps: which findings to fix first, and offer `/letsbuild` on the top one.

## What it does NOT do
- It does not fix anything (read-only discovery). Fixes go through the normal `/letsbuild` → ship
  path so they get the plan gate and the diff-scoped review.
- It does not replace `/code-review` (diff, cheap, automatic on ship) or `/code-review ultra`
  (cloud diff review). This is subsystem/root-cause DISCOVERY, deeper and broader than any diff.

## Tuning
- Depth vs cost: `maxRounds` (default 6, loop stops early at 2 dry rounds) and `maxVerify`
  (default 50 candidates verified) trade coverage for spend. The `budget.total` from a `+Nk`
  directive is the hard ceiling — finders stop spawning new rounds under the floor.
- The six hunting lenses live in `audit-workflow.js` (`DIMENSIONS`). Add a lens there if a target
  needs one (e.g. a perf or migration-safety lens); keep each lens concrete and refutation-first.
