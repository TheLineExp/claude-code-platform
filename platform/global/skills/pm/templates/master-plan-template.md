# {{project_name}} — Master Plan

> Single source of truth. The PM skill parses this file to generate dev briefs, status, and milestone scope. Decisions made here override individual dev windows.

## Context

{{project_context}}

**Acceptance criteria for "done":**

{{global_acceptance_criteria}}

---

## Status snapshot — {{date}}

### What's shipped

| PR | Chunk | What | Status |
|---|---|---|---|

### What's still pending

{{pending_summary}}

---

## Decisions made (override in writing if you disagree)

{{decisions_locked}}

## Open questions still to resolve

{{open_questions}}

---

## Phased plan — chunks ordered for context cleanliness

Each chunk is sized to **one PR** unless explicitly grouped. Window assignment minimizes cross-window file collisions.

### Track {{track_id}} — {{track_name}}

| Chunk | Owner | What | Repo | Depends on | LOC est |
|---|---|---|---|---|---|
| **{{chunk_id}}** | {{owner}} | {{description}} | {{repo}} | {{deps}} | {{loc}} |

---

## Window playbooks (so we don't step on each other)

| Window | Owns | Avoids |
|---|---|---|
| **{{window}}** | {{chunks_owned}} | {{areas_avoided}} |

Cross-window touch zones (additive only): {{shared_zones}}

---

## Critical files (by chunk)

- **{{chunk_id}}**: {{file_paths}}

## Reuse (don't re-build)

- {{reuse_pointers}}

## Verification (per chunk, end-to-end on staging)

- **{{chunk_id}}**: {{verification_steps}}

## Out of scope (explicit)

- {{out_of_scope_items}}

---

## Recommended sequencing

{{sequencing_narrative}}
