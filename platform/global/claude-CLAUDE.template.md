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
`outside-reviewer` at shipit Step 4b (one pass on final head, diff-scoped), backlog hook confirms every park.

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

# Review agents — ONE pass on final head, scoped to the DIFF (not every fix round)
- **Frequency + scope (all three):** run ONCE, on the FINAL HEAD, against the DIFF (changed
  surface + its direct sibling call sites) — NOT the full context, and NOT after every
  review-fix round. Local fix rounds stay at the source and converge there; the fleet does
  NOT re-fire per round. If the one final-head pass surfaces an issue, fix it and re-review
  ONLY that reviewer's own domain on the changed lines — never re-run the whole fleet from
  scratch. (Cost fix 2026-07-17: the per-fix-round fleet re-run was ~74% of subagent burn.)
- **parity-sweep**: diffs touching payments/refunds/vouchers, state transitions, shared
  helpers/serializers, auth gates, configs, or concurrency → one pass on final head over the
  diff + its sibling call sites.
- **money-concurrency-reviewer**: one pass on the FINAL HEAD of a money-path change. KEEP its
  whole-call-chain reading for the money paths IN THE DIFF — never judge money code from a
  snippet; this is the P1 guardrail — but it runs once, not per round.
- **outside-reviewer / Codex**: one pass on final head (shipit Step 4b), context-isolated
  (diff + spec only). Codex still finds the issues — it just runs once, on the diff, before
  push, not on every fix round. Purpose: Codex converges in ≤1 round instead of 4–8.

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
- **Subagent bounds (2026-07-17 cost fix — subagent runs were a median 76 turns / 5.3M tokens,
  max 90M):** a search/read offload (`Explore`, `general-purpose`) must be TIGHTLY scoped and
  SHORT (~5–15 tool calls) — hand it the file/symbol/diff, not an open-ended hunt; needing 50+
  reads means it was mis-scoped, so split it into targeted lookups. **Runaway backstop:** ANY
  subagent (reviewers included) past ~200 tool calls is almost certainly LOOPING — stop, report
  what you have, and LOUDLY flag that you hit the ceiling so the caller can re-scope; never
  silently truncate a money review.

# graphify — optional aid, never a gate
- Use `/graphify` queries when a fresh graph exists; a graph older than HEAD lies — refresh
  free with `graphify update <repo> --force` or skip it. Never set `ANTHROPIC_API_KEY`.

# Session & context discipline
- **One feature per session.** After `/shipit` completes (or a feature is verified), END the
  session and start the next task fresh — marathon sessions burn context and hit compaction.
- **Keep the main thread lean (2026-07-17 — main ran at ~227k context/turn, half of it re-read
  file/command output).** Big reads (whole files, long logs, broad greps) go to a CHEAP scoped
  subagent that returns only the conclusion — NOT into the main context, where every later turn
  re-reads them. Compact/rotate at every feature boundary and any time context passes ~150k;
  don't let a window marathon.
- **Quote every path** — `"Volo Technologies"` contains a space; the `~/vt` symlink points
  there, prefer it in commands.
- **Subagent prompts** must state the absolute working directory (worktree root) on the
  first line and require absolute paths in all commands.
- Report results as conclusion + pointers (`path:line`, verified PR link) — never paste
  dumps, briefs, or plan bodies.
- **⛔ HARD RULE — every M report, every handoff, every sitrep: RECAP, then NUMBERED NEXT STEPS.**
  Mike ACTS on that output. **(1)** Lead with a clean, concise statement of what the project is
  and where we are — always first, no exceptions. **(2)** Then his next steps, numbered **in
  paste order** ("Step 1, 2, 3"), each directly actionable (paste-ready prompt / exact command /
  specific decision); when several report-to-M windows need launching, stage them in the exact
  order to paste. **(3)** Name the step that matters most if one dominates. **(4)** Findings,
  evidence, and reasoning go in the artifacts (`~/.claude/pm/<project>/`) and are referenced BY
  PATH — never in the reply. **(5)** Every PR carries its full clickable URL, never a bare
  `#number`. Self-trigger: if a reply opens with anything but the recap, STOP and rewrite.
  Governs `/pm` (M — every subcommand's OUTPUT, not just chat replies) + `/handoff` (all modes)
  + `/sitrep`. **Canonical full text — the ONLY copy, with the gold-standard worked example:
  `~/.claude/skills/sitrep/FORMAT.md`.** Change the rule THERE; all other mentions point to it.
- **`/sitrep` = that report on demand — any window, any project, read-only.** `/sitrep` (active),
  `/sitrep <project>` (PM or memory-tracked: `/sitrep w114`), `/sitrep all`, `/sitrep prs` (open
  PRs everywhere + merge URLs). Use it whenever asked "where are we / what's next / status".
