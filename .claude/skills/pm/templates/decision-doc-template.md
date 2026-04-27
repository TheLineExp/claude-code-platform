# {{topic}} — Decisions Doc

> {{n_questions}} open questions that block {{blocked_chunk}} coding. Read top to bottom, fill in each `Decision:` line, hand back. No code starts until all are answered.

---

## Trigger recap

{{trigger_description}}

**Routing decision (M):** {{routing_summary}}

---

## Phasing summary

| Phase | Scope | LOC est. | Risk | Ships |
|-------|-------|----------|------|-------|
| **1** | {{phase_1_scope}} | {{loc_1}} | {{risk_1}} | {{ships_1}} |

---

## Decision 1 — {{title_1}}

**Problem.** {{problem_1}}

**Options.**

1. **{{option_1a}}** — {{description_1a}}
   - Pros: {{pros_1a}}
   - Cons: {{cons_1a}}

2. **{{option_1b}}** — {{description_1b}}
   - Pros: {{pros_1b}}
   - Cons: {{cons_1b}}

**Recommendation.** {{recommendation_1}}

**Decision: ___**

---

## After all decisions are filled in

1. M hands back the answered version via `/pm decisions answer <topic> <answers>`.
2. Dev runs `/letsbuild`, sets up the feature branch, and ships.
3. Subsequent phases each get their own decision doc as needed.

No code starts until this doc is returned with all `Decision:` lines populated.
