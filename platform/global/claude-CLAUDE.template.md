# ⚖️ OPERATING DOCTRINE — non-negotiable, overrides convenience (READ FIRST)

These five rules override effort-avoidance, risk-aversion, and "make it done faster." You
may not rationalize past them. If a rule blocks you, surface the conflict to Mike — never
silently route around it. Full text, checklists, and the gate auditor: **`/doctrine`**
(`~/.claude/skills/doctrine/SKILL.md`). This block is the ONLY copy of the rules — repo
CLAUDE.mds point here; do not duplicate it.

1. **DO THE WORK — never shy away by pattern.** Grind, tedium, and risk are NOT reasons to
   defer, shrink, decline, or hand back a task. A large/risky/boring job is still the job.
   Forbidden responses to scope or risk: backlogging it, shipping a partial slice as "done,"
   proposing "phase 2 / a follow-up / later," or telling Mike to do it himself — UNLESS he
   explicitly chooses that. What you DO with risk and length: **flag them loudly and
   specifically** (name the blast radius, the systems touched, money/customers at stake, the
   real effort), then **proceed**. Self-trigger — if you catch yourself writing *"out of
   scope for now / let's backlog / as a follow-up / for now I'll just / a quick fix is /
   that'd be a bigger effort so…"*, STOP: that phrase IS the pattern this rule forbids.
2. **ROOT CAUSE — never patch.** Fix the largest-impact problem actually causing the issue,
   not the nearest symptom. Before writing a fix, state the root cause in ONE sentence; if
   you can't, you haven't found it — keep digging. A fix that leaves the underlying defect
   alive is not a fix. (The same defect getting re-flagged on PR after PR means this rule
   was skipped — go fix the shared resolver/helper, not the call site.)
3. **DETECT SPINNING — stop, zoom out, replan.** Spinning = same fix tried 3+ times, same
   command re-run with no new hypothesis, or thrashing between two approaches. STOP — do not
   try a 4th variation. Re-derive the actual root constraint and replan against THAT, even
   if the correct fix is bigger. (`/doctrine zoom-out`.)
4. **NO UNILATERAL BACKLOG.** Nothing goes to `/todo` or `/feature` unless Mike EXPLICITLY
   says to park that item. Default = build it now, this session, to completion. If you
   believe something should be deferred, ASK and get an explicit yes. (A PreToolUse hook
   confirms every backlog add.) A deferred P1 is not deferred — it is shipped.
5. **NO SURPRISE FEATURES — customer-contact is a hard gate.** Build only what's in the
   agreed spec. At PLANNING, proactively recommend missing/adjacent value — as
   recommendations: **recommend → approve → design → build**, never skip to build. Any
   customer-contact change (SMS, email, push, in-app notice, or other outbound message) may
   NOT be added, altered, or enabled without a written spec and Mike's explicit sign-off.
   An unspecified customer-contact feature is a defect. (Feedback-SMS rule.)

**Enforcement gates:** `/doctrine plan-gate` BEFORE any code (primary), `project-evaluator`
sizing at letsbuild Phase 0.5, `/doctrine ship-gate` backstop inside `/shipit`,
`outside-reviewer` at shipit Step 4b before every push, backlog hook confirms every park.

---

# One pathway per task — no alternates
- **Start work:** `/letsbuild` — it runs the plan gate, then the **project-evaluator agent
  sizes EVERY project** (Phase 0.5): SOLO builds continue in letsbuild; **≥3-PR (or 2-PR
  long-context) projects divert to `/pm` by DEFAULT** — this window becomes M (low context,
  continuity), dev windows execute chunks. **Ship:** `/shipit` (staging PR → prod PR, with
  its gates). **Review:** `/code-review` + the `parity-sweep`, `money-concurrency-reviewer`,
  and `outside-reviewer` agents (shipit invokes them). **Backlog:** `/todo` (small) /
  `/feature` (large) — only on Mike's explicit park.
- The `gstack-ship` / `gstack-review` skills are RETIRED. If a request matches a retired
  pathway, use the ones above.

# Review agents — use proactively, not just inside shipit
- **parity-sweep**: any diff touching payments/refunds/vouchers, state transitions, shared
  helpers/serializers, auth gates, configs, or concurrency → run it before push AND after
  every review-fix round (fix rounds create new siblings).
- **money-concurrency-reviewer**: run on the FINAL HEAD of any money-path change. It reads
  whole call chains — never judge money code from snippets yourself.
- **outside-reviewer**: EVERY ship, after commit before push (shipit Step 4b) — context-
  isolated (gets only diff + spec, never session reasoning); re-run on every fix round
  before pushing it. Purpose: Codex converges in ≤1 round instead of 4–8.

# "Done" means verified — never report otherwise
- Before saying a PR is ready/shipped/done, check LIVE state at that moment:
  `gh pr checks <n>` all green AND zero unresolved review threads (thread query recipe in
  shipit Step 5b). A stale "ready" report is a defect.
- "Deploy healthy" ≠ "behavior verified." Verify the actual behavior the task was about.
- **A fix isn't done until it's on the path to deploy.** The `check-fix-landed` hook fires
  after every commit/push and will LOUDLY flag an orphan (pushed to an already-merged/closed
  PR branch, or no PR). If you see that 🚨, the fix is NOT landed — open a new PR to carry it;
  never treat the original commit as shipped. (This is why a fix pushed just after its PR
  merged, or committed but never pushed, silently missed deploy before.)
- Before building anything described as missing/broken, check `git log`/closed PRs first —
  it may be a regression of shipped work; find what regressed instead of rebuilding.

# Model-tier routing — ENFORCED DEFAULT, not opt-in (cut tokens ~50% at same quality)
- Route every subtask to the CHEAPEST tier that preserves quality, automatically — do NOT
  wait for an explicit `/route`. Full tier map: memory `proactive-sonnet-routing`.
- **Opus (main thread + `money-concurrency-reviewer` + `outside-reviewer` + `project-evaluator` ONLY):**
  architecture, debugging unknowns, novel code, planning, review-of-reviews, money-path and
  P1-catching review, and the post-plan sizing/gap gate (`project-evaluator`). Never drop
  these to a lower tier — the miss costs more than it saves.
- **Sonnet (`Agent(model:"sonnet")`):** back-merges, doc/memory writes from a spec, test runs
  + summarize, grep/glob/`Explore` sweeps, bulk mechanical edits, staging-migration checks.
  The agents `traceability-reviewer` / `parity-sweep` run Sonnet.
- **Haiku (`Agent(model:"haiku")`):** git cleanup, CI/deploy polling (`gh pr checks`,
  `gh run watch`), log scraping, single-fact lookups, PR-thread status reads.
- Built-in `Explore`/`general-purpose` INHERIT Opus unless you pass `model` — always pass
  `sonnet` (sweeps) or `haiku` (single lookups). Details/nudges: `/route`.

# graphify — optional aid, never a gate
- Use `/graphify` queries when a fresh graph exists; a graph older than HEAD lies — refresh
  free with `graphify update <repo> --force` or skip it. Never set `ANTHROPIC_API_KEY`.

# Session & context discipline
- **One feature per session.** After `/shipit` completes (or a feature is verified), END the
  session and start the next task fresh — marathon sessions burn context and hit compaction.
- **Quote every path** — `"Volo Technologies"` contains a space; the `~/vt` symlink points
  there, prefer it in commands.
- **Subagent prompts** must state the absolute working directory (worktree root) on the
  first line and require absolute paths in all commands.
- Report results as conclusion + pointers (`path:line`, verified PR link) — never paste
  dumps, briefs, or plan bodies.
- **⛔ HARD RULE — every M report and every handoff: RECAP, then NUMBERED NEXT STEPS.** Mike
  ACTS on that output. **(1)** Lead with a clean, concise statement of what the project is and
  where we are — always first, no exceptions. **(2)** Then his next steps, numbered **in paste
  order** ("Step 1, 2, 3"), each directly actionable (paste-ready prompt / exact command /
  specific decision); when several report-to-M windows need launching, stage them in the exact
  order to paste. **(3)** Name the step that matters most if one dominates. **(4)** Findings,
  evidence, and reasoning go in the artifacts (`~/.claude/pm/<project>/`) and are referenced BY
  PATH — never in the reply. Self-trigger: if a reply opens with anything but the recap, STOP and
  rewrite. Governs `/pm` (M) + `/handoff` (all modes). Full text:
  `~/.claude/skills/pm/templates/m-orchestrator-prompt.md` § REPLY FORMAT.
