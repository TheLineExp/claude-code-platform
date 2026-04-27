# Acceptance Log

> Per-chunk acceptance evidence. Devs fill in checkbox boxes + evidence; M reviews. `/pm ship` refuses to mark a chunk shipped if its checklist is incomplete (override with `--force`, logged).

---

## {{chunk_id}} — {{chunk_title}}

**Status**: {{status}}
**PR**: {{pr_number}}
**Filed by**: {{dev_window}} on {{filed_date}}
**Reviewed by**: M on {{reviewed_date}}

### Acceptance checklist

- [ ] {{criterion_1}}
  - **Evidence**: {{evidence_1}}
- [ ] {{criterion_2}}
  - **Evidence**: {{evidence_2}}

### Test coverage

- Tests added: {{tests_added}}
- Coverage delta: {{coverage_delta}}
- Suite total after merge: {{suite_total}}

### Brief acceptance criteria (from master plan)

{{brief_acceptance_text}}

### Cross-system touch points verified

- [ ] No file-ownership boundary crossed
- [ ] No regressions in other windows' acceptance criteria
- [ ] All decisions inherited from master plan respected

### M review notes

{{m_review_notes}}

### Outcome

- [ ] Approved for `/pm ship`
- [ ] Held — needs follow-up: {{followup}}
- [ ] Rejected — needs rework: {{rework}}
