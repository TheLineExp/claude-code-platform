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
3. Implement, write tests, run tests, `/shipit`.
4. Report back to M with: `{{chunk_id}} merged at <PR#>. <test count> tests added. Acceptance evidence filed.`

## LOC budget

If your scope grows past **{{loc_estimate}} × 1.5** ({{loc_threshold}}) production LOC, **stop and ping M before exceeding**. M will route to one of:
- Approve over-budget (single PR, with rationale)
- Split into multiple PRs (with sequencing plan)
- Trim scope (with explicit cuts)

## Verification commands

{{verification_commands}}

## Status reporting back to M

Report each PR merge in this exact format so M's `/pm verify` can parse it. **Include the full
PR URL** — M relays it to Mike, who merges from it, and a bare `#number` breaks that chain
(memory: `always-give-pr-link`):

```
{{chunk_id}} merged at #<PR> (https://github.com/TheLineExp/<repo>/pull/<PR>). {{tests_count}} tests added. Acceptance: {{acceptance_status}}.
```

If you hit a blocker, run:
```
/pm blocked {{window_id}} {{chunk_id}} <one-line reason>
```

**If you report to Mike directly** (not to M), the reply format is a HARD RULE: recap first, then
numbered paste-order next steps — spec at `~/.claude/skills/sitrep/FORMAT.md`. The terse
one-liner above is for M's parser only; it is not a reply to Mike.

## Hard rules

- Never `--no-verify`, never `git reset --hard`, never `git push --force`.
- Never delete unmerged branches.
- Never touch files in the "must NOT touch" list above.
- If you find yourself implementing across the boundary into another window's scope, stop and ping M.
