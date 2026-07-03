# PR Review Convention

Local-first: reviews run on this machine at $0 GitHub-Actions cost, with Codex as an
external safety-net. The agent gates exist because two weeks of review data
([AUDIT-2026-07-02.md](AUDIT-2026-07-02.md)) showed most P1/P2s live in code the diff did
NOT touch (~65% missed-sibling-surface) or in TOCTOU/race interleavings (~40% of P1s).

## The reviewers

| Reviewer | Where it runs | Role |
|----------|---------------|------|
| `/code-review` (built-in) | Locally, from the worktree | Primary diff review; `--comment` posts inline on the PR |
| `parity-sweep` agent | Locally, run by `/shipit` | Blast-radius sweep — sibling call sites, twin routes, config surfaces the diff didn't change |
| `money-concurrency-reviewer` agent | Locally, run by `/shipit` | Adversarial TOCTOU/race review on money paths (final HEAD, and again after every fix round) |
| `traceability-reviewer` agent | Locally, on demand / via `/traceability-review` | End-to-end call-chain verification for multi-layer changes |
| Codex | GitHub Actions, gated to `ready_for_review` (concurrency-cancelled) | External safety-net |

`gstack-review` is retired — the review pathway is `/code-review` + the agents above,
orchestrated by `/shipit`.

## Sequence per ship

1. **Before push:** `/code-review` on `git diff origin/staging...HEAD`; fix every finding.
2. **Before push, for payment/state/shared-helper/auth/concurrency diffs:** run
   `parity-sweep` and `money-concurrency-reviewer`; fix to PASS. Re-run both after every
   review-fix round — fixes introduce new bugs.
3. **Draft PR:** nothing fires; iterate freely.
4. **Mark ready-for-review:** Codex fires once. But "ready" itself is gated — the
   **PR-Ready gate** in `/shipit` requires checks green + **zero unresolved review
   threads** on the current HEAD before any "ready" claim.
5. **Prod promotion:** staging must be converged first (prod-promotion gate), then the
   staging → prod PR.

## Responding to comments

1. **One pass per HEAD.** Triage ALL inline comments (Codex + Claude) in a single pass.
2. **Fix or reply-and-resolve.** Every finding is fixed (reference the commit) or replied
   to with rationale, then resolved. No silent dismissals.
3. **Dedup overlaps** — address once, note "covers both".
4. **Re-review after the fix pass** (including re-running the two agents for gated change
   types), then merge once clean on the new HEAD.

## Primary/fallback swap

Either reviewer can hit limits. Swap with a repo variable — no file edits:

```bash
gh variable set REVIEW_PRIMARY --body claude   # Codex rate-limited → lean on local Claude
gh variable set REVIEW_PRIMARY --body codex    # Opus quota hit → re-enable Codex Actions
```

The Actions workflows read `vars.REVIEW_PRIMARY` in their top-level `if:` and self-gate.

## Never

- Never claim a PR is "ready" with failing checks or unresolved threads (PR-Ready gate).
- Never merge with a pending or unaddressed review on the current HEAD.
- Agents never merge any PR — only Mike merges (enforced by hooks).
