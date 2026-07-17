# ⛔ THE REPLY FORMAT — canonical spec

> **This file is the ONLY full copy of the reply-format rule.** `/sitrep`, `/handoff` (every
> mode), `/pm` (every reply from M), and the M-orchestrator prompt all point HERE. Consumers
> carry a compressed ⛔ pointer block so a window that never reads this file still complies —
> but the elaboration, the worked example, and the failure modes live only here. **Change the
> rule here.** If you find a competing full copy elsewhere, that copy is drift — delete it and
> point it at this file.

Governs: `/sitrep` · `/handoff` (checkpoint, resume, where, list) · `/pm` (every M reply) ·
every dev→M report-back · every handoff prompt · every session-end summary.

---

## The rule

**Every report to Mike is: the RECAP, then his NUMBERED NEXT STEPS. Nothing else leads.**

Mike is the one who ACTS on this output — he launches the windows, pastes the prompts, merges
the PRs, flips the settings. A report that opens with findings leaves him with no idea what to
do while the window scrolls on, and the work stalls. This is not a style preference. It is the
difference between the output working and the output being noise.

## Required shape — every time, no exceptions

1. **Recap first — always.** A clean, concise statement of *what the project is* and *where we
   are*. Never open with a finding, a root cause, a "the good news is", or any paragraph before
   the recap.
2. **Then numbered next steps, in paste order.** "Step 1, Step 2, Step 3." Each is directly
   actionable: a paste-ready prompt, an exact command, or a specific decision. When several
   windows need launching, stage them in the exact order Mike should paste them.
3. **Name the step that matters most** when one dominates — "If you only do one thing, do Step 1."
4. **Analysis does NOT go in the reply.** Findings, evidence, review verdicts, risk narratives →
   `~/.claude/pm/<project>/` (`status.md`, `reviews/`, `decisions/`, `reports/`) or a `/handoff`
   snapshot. Reference them **by path**. Mike reads them if he wants them; he must never wade
   through them to find his next action.
5. **Every PR gets its full clickable URL** — `https://github.com/TheLineExp/<repo>/pull/<n>`,
   never a bare `#1574`. If a PR is mergeable now, the step IS the merge link. (Memory:
   `always-give-pr-link`. Merges are Mike's — never merge for him. Never `--squash`; hand him
   the `--merge` command. Memory: `never-squash-merge`.)

## Self-trigger

If you are about to open a reply with anything other than the recap — STOP and rewrite. If your
reply has no numbered steps, it has failed at its only job. If a "step" isn't something Mike can
paste, run, or decide in one action, it isn't a step yet — sharpen it or move it into the artifact.

---

## The canonical shape

```
**The project**
<One short paragraph: what it is, the asks, the deadline/pressure.>

**Where we are**
Done — <what's merged/live, with PR links>
Blocked — <what's stuck, behind WHAT single thing, and what it's gating>
In flight — <what's running now, or "nothing" — and say why that matters>

**Your next steps**
Step 1 — <title>. <one line of why this is first.>
<paste-ready prompt / exact command / the decision to make>

Step 2 — <title>. <why.>
<paste-ready block>

Step 3 — <title>. <why.>
<paste-ready block>

If you only do one thing, do Step <N>.
```

**Rules of thumb**
- Recap ≤ 6 lines. If it needs more, the excess is analysis → artifact.
- `In flight: nothing` is a finding, not a gap — say it, and say why it makes Step 1 urgent.
- A blocked list is only useful if it names the ONE thing unblocking it. "Blocked on staging red"
  → say what the fix is and which step lands it.
- Prompts to paste name the absolute working dir and the brief path — never the brief body
  (`/pm brief` hard rule).

---

## Worked example — the gold standard

Mike's own words, 2026-07-16, marked **"THIS IS PERFECT"**. Match this shape.

> **The project**
> Vouchers launch booking-flow improvements. Three asks: (1) scanning a voucher QR preselects a
> preferred location + bike, (2) fix the mobile zip/country bleed, (3) weight required only for
> full-suspension bikes. Launch is EOW.
>
> **Where we are**
> Done — merged to staging: P1 (mobile bleed fix), P2 (bike-type weight flag), P3
> (preferred-choice config).
>
> Blocked — everything else, behind one thing. Reservations staging is red from a defect that
> isn't ours (#1570 + #1571 collided). The fix is two lines in a test file. Until it lands, no
> reservations PR can merge — that's P4, P5, P6, P7, and P8.
>
> In flight: nothing. That's why Step 1 matters most.
>
> **Your next steps**
>
> Step 1 — launch dev-E on S1. This is the only thing that unblocks the track. Fresh window at
> /Users/mikekunz/Documents/Volo Technologies/fleetmanager-reservations:
>
> > You are Dev-E on PM project vouchers-booking-flow-improvements, Track S. Read
> > ~/.claude/pm/vouchers-booking-flow-improvements/reviews/2026-07-17-union-money-review.md
> > FIRST, then your brief at ~/.claude/pm/vouchers-booking-flow-improvements/briefs/chunk-S1.md.
> > Execute S1: the fix is 2 test lines. selfService.js is forbidden — the production code is
> > correct. Then do S2 (one line in deploy.yml:118), then S3. Report back to M.
>
> Step 2 — launch dev-A on P7. Can build now in parallel; merges after Step 1 lands. Fresh
> window at the same repo path:
>
> > You are Dev-A on PM project vouchers-booking-flow-improvements, fresh window. Read your brief
> > at ~/.claude/pm/vouchers-booking-flow-improvements/briefs/chunk-P7.md and the frozen contract
> > at ~/.claude/pm/vouchers-booking-flow-improvements/decisions/2026-07-16-preferred-bike-type-domain.md.
> > Execute P7 (preselect on voucher arrival). Staging's Backend check is red from an unrelated
> > defect — build and open your PR anyway; it merges once S1 lands. Report back to M.
>
> Step 3 — confirm P2's migration is deployed on FM V3 staging. That unblocks P4. Once it's live,
> tell me and I'll give you the dev-B prompt.
>
> If you only do one thing, do Step 1.

**Why this one works** — study it before writing yours:
- The recap is 3 sentences and names the *deadline*. No history.
- "Blocked — everything else, behind one thing" names the single unblocker and what it gates.
- "In flight: nothing. That's why Step 1 matters most." — turns an absence into the argument.
- Every step is *literally pasteable*. Step 3 is a decision + a promise of the next prompt.
- The union-money review is referenced BY PATH. Its findings are nowhere in the reply.
- It closes by naming the dominant step.

---

## Why this rule exists

Mike, 2026-07-16, verbatim:

> *"when i report back to M, M is supposed to give me the very next step. instead i have gotten a
> ton of crap — no direct responses and no direct instructions… I want M to give me clear and
> concise next steps directly for any report back to M windows. then i can act on them before
> moving to the next things."*

And on the shape above, 2026-07-16: *"THIS IS PERFECT — Now make this the standard for all
handoff skills and all M reports. make it a HARD rule."*

Memory: `m-next-step-reporting`.
