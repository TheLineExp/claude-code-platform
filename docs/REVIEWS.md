# PR Review Convention

The review model is deliberately **local-first** to keep GitHub Actions minutes low while
still getting two independent reviewers (Claude + Codex) with inline comments on the diff.

## The model

| Reviewer | Where it runs | Cost | Role |
|----------|---------------|------|------|
| **Claude** | **Locally**, via `/code-review --comment` from your worktree | $0 Actions | **Primary** inline reviewer |
| **Codex** | GitHub Actions (`codex-auto-request.yml`) | Actions minutes | Automated safety-net |
| `@claude` | GitHub Actions (`claude-mention.yml`) | Actions minutes | Human-triggered follow-ups only |

Claude's auto-review **does not** run as a per-push Action (that was the #1 minute-burn).
You run it on your machine, on demand, and it posts inline alongside Codex's comments.

## When reviews fire (timing)

- **Draft PR:** nothing fires. Iterate freely.
- **Mark ready-for-review:** Codex fires **once** (gated to the `ready_for_review` event,
  with `concurrency: cancel-in-progress` so rapid pushes don't stack runs).
- **Before requesting merge:** run `/code-review --comment` locally to add Claude's pass.
- The merge gate is **"current HEAD has zero unresolved findings from the active primary
  reviewer"** — not elapsed wall-clock time.

## Primary / fallback swap (one command)

Either reviewer can hit rate/usage limits (Codex hits rate limits often). Swap with a repo
variable — no file edits, no redeploy:

```bash
gh variable set REVIEW_PRIMARY --body claude   # Codex rate-limited → lean on local Claude
gh variable set REVIEW_PRIMARY --body codex    # Opus weekly quota hit → re-enable Codex Actions
gh variable set REVIEW_PRIMARY --body both      # belt-and-suspenders (burns more minutes)
```

The Actions workflows read `vars.REVIEW_PRIMARY` in their top-level `if:` and self-gate.
Default: `codex` (Codex Actions on) + local Claude always available on demand.

## Responding to comments (the consistency rule)

The thing that was inconsistent before: who replies, and when. The rule:

1. **One pass per HEAD.** The PR author (you, or the dev agent) triages **all** inline
   comments — Codex's and Claude's — in a single pass, not per-comment drip.
2. **Fix or reply-and-resolve.** Every finding is either fixed in code (reference the fix
   commit in the reply) **or** replied to with explicit rationale, then resolved. No silent
   dismissals.
3. **Dedup overlaps.** When Codex and Claude flag the same line, address it once and note
   "covers both" — don't write two replies.
4. **Re-review after the fix pass**, then merge once the active primary reviewer is clean on
   the new HEAD.

## Never

- Never merge with a pending or unaddressed review on the **current** HEAD.
- Agents never merge any PR — only the human merges (enforced by hooks).
