# Dev Brief Template

> Used by `/pm brief <chunk-id>` to generate per-window handoff prompts. Placeholders in `{{...}}` get filled from the master plan parse.

---

# Dev-{{window_id}} — chunk {{chunk_id}} ({{chunk_title}})

> Cherry-picked from master plan at `{{master_plan_path}}`. Read that for full context. This file is your scoped working set.

## Your scope

{{chunk_description}}

**Track**: {{track_name}}
**Estimated LOC**: {{loc_estimate}} (production)
**Dependencies**: {{dependencies}}
**Repo(s)**: {{repos}}

## Files you own (don't touch from other windows)

{{files_owned}}

## Files you must NOT touch

{{files_forbidden}}

## Cross-window touch zones (additive only)

{{additive_zones}}

## Decisions already made (don't relitigate)

{{decisions_inherited}}

## Acceptance criteria

{{acceptance_checklist}}

When all boxes are ticked, file evidence via:
```
/pm acceptance {{chunk_id}}
```

## Workflow

1. From the appropriate repo's main path, run `/letsbuild` → creates worktree, branch, registers.
2. Open a NEW Claude Code window at the worktree path.
3. Implement, write tests, run tests, `/shipit` (opens the PR — does NOT merge).
4. When the PR is open, CI is green, and local reviews are clean, report to M: `{{chunk_id}} READY at #<PR>. <test count> tests added. Acceptance evidence filed.` **Do NOT merge and do NOT report "merged" — agents never merge. M reviews/accepts the READY PR, the user merges, then M runs `/pm verify` to confirm it landed.**

## LOC budget

If your scope grows past **{{loc_estimate}} × 1.5** ({{loc_threshold}}) production LOC, **stop and ping M before exceeding**. M will route to one of:
- Approve over-budget (single PR, with rationale)
- Split into multiple PRs (with sequencing plan)
- Trim scope (with explicit cuts)

## Verification commands

{{verification_commands}}

## Status reporting back to M

Dev windows **NEVER merge** — only the user merges. When your PR is open, CI is green, and
local reviews are clean, report to M in this exact format:

```
{{chunk_id}} READY at #<PR>. {{tests_count}} tests added. Acceptance: {{acceptance_status}}.
```

Do NOT merge and do NOT report "merged." Two distinct M gates, don't conflate them: **before**
the user merges, M reviews/accepts the READY PR (acceptance + milestone gate); **after** the
user merges, M runs `/pm verify <PR>` to confirm it landed on origin (the spec checks the merge
commit, so it only works post-merge). If a review thread lands, fix it in one pass, reply
INLINE on each thread (never a bottom-of-PR summary), re-run the required reviewers, and
re-report READY.

If you hit a blocker, run:
```
/pm blocked {{window_id}} {{chunk_id}} <one-line reason>
```

## Hard rules

- Never `--no-verify`, never `git reset --hard`, never `git push --force`.
- Never delete unmerged branches.
- Never touch files in the "must NOT touch" list above.
- If you find yourself implementing across the boundary into another window's scope, stop and ping M.
