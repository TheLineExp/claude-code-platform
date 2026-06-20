<!-- UNIFIED cross-repo QUALITY-SWEEP backlog. Maintained by the /todo skill (~/.claude/skills/todo/SKILL.md).
     Spans ALL FleetManager repos: reservations / FM V3 / vouchers / azure-ops.
     This file lives in the claude-code-platform repo (backlog/TODO.md) and is git-synced
     across every dev machine. The /todo skill pulls before reading and commits+pushes after writing.
     SCOPE: small, well-defined, lower-pri fixes/tweaks + ops/cleanup — groupable into a quality sweep.
     Distinct from: /feature (LARGE, undefined projects — backlog/FEATURES.md) and MASTER_PLAN.md (phase tracking).
     Item format:  - [ ] (ID) [repo-or-area] **title** — short note / link
     ID scheme: FF# = fast follow-up/fix, OPS# = ops/cleanup. Keep IDs stable; never renumber.
     Mark done: change [ ] → [x] and move under "Done (recent)" with a YYYY-MM-DD stamp. -->

# 🗂️ Backlog — quality-sweep tasks across all FleetManager repos

_Last touched: 2026-06-20_

## 🔥 Fast follow-ups
_(small, discrete, ship-soon items — fixes, tweaks, residuals)_

- [ ] (FF1) [reservations] **Early pickup: surface the same-day shift in the public slot builders** — backend accepts post-cutoff same-day full/half/hourly (shift to next open morning), but `computeFullDayBlocks` / `sameDayBlockGraceExpired` / hourly-future-only still drop those slots, so a customer can't select them. Feature gap, not a regression (those were never publicly bookable). Make the slot builders keep post-cutoff shifted slots when `earlyPickupEnabled`. (Codex #94 on PR #1086.)
- [ ] (FF2) [reservations] **Early pickup: DB race trigger ignores physicalStartTime** — the `20260513000000_p2_idempotency_race_safety` trigger enforces no-overlap on `Reservation.startTime/endTime` only, NOT `physicalStartTime`. Concurrent creates whose billed windows don't overlap but whose early-pickup evening HOLDS do could both pass. Pre-existing since x20 same-day early pickup; app-level `holdOverlapOR` covers the normal path. Fix: extend the trigger (migration) to also enforce `physicalStartTime`-based overlap. (Codex #89 on PR #1086.)

## 🧹 Ops / cleanup

## ✅ Done (recent)
<!-- move completed items here with a date; prune periodically -->
