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

_Last touched: 2026-06-22_

## 🔥 Fast follow-ups
_(small, discrete, ship-soon items — fixes, tweaks, residuals)_

- [ ] (FF1) [reservations] **Early pickup: surface the same-day shift in the public slot builders** — backend accepts post-cutoff same-day full/half/hourly (shift to next open morning), but `computeFullDayBlocks` / `sameDayBlockGraceExpired` / hourly-future-only still drop those slots, so a customer can't select them. Feature gap, not a regression (those were never publicly bookable). Make the slot builders keep post-cutoff shifted slots when `earlyPickupEnabled`. (Codex #94 on PR #1086.)
- [ ] (FF2) [reservations] **Early pickup: DB race trigger ignores physicalStartTime** — the `20260513000000_p2_idempotency_race_safety` trigger enforces no-overlap on `Reservation.startTime/endTime` only, NOT `physicalStartTime`. Concurrent creates whose billed windows don't overlap but whose early-pickup evening HOLDS do could both pass. Pre-existing since x20 same-day early pickup; app-level `holdOverlapOR` covers the normal path. Fix: extend the trigger (migration) to also enforce `physicalStartTime`-based overlap. (Codex #89 on PR #1086.)
- [ ] (FF3) [reservations] **Public booking: explicit-hourly resume key mismatch** — `useDateSelection.js` hydrates `timeBlockKey` to a numeric start-hour, but explicit hourly `BookingSlot` keys are strings, so on resume of a saved explicit-hourly booking the start-time card shows "Start time…" (not "Starts X") and the `SET_DATES` hourly branch can fail to re-commit. Pre-existing in the hook's hydration; surfaced by the flattened block grid (PR #1101). Fix: add a `matchedKeyRef`-style match (as in FM V3 `ScheduleEditor`) that maps the incoming startTime to a resolved hourly slot key once slots resolve.
- [ ] (FF4) [reservations] **Build the last two bug-family detectors — F2 (flag-threading) + F9 (stale-async)** — the remaining 🔶 families in `docs/BUG_FAMILIES.md`. Build each via the draft→Codex-to-zero loop (Engine 2). F2: a flag/bypass honored at one gate but re-rejected by a downstream sibling (the `allowClosedDays` / `getStripeContext`-cutover class). F9: an in-flight async write with no generation token, or a `useState(initial)` that never re-syncs across a refetch. `harvest-codex-findings.js` ranks them when they recur. Detectors F1/F4/F5/F6/F7/F8/F10 already shipped.

## 🧹 Ops / cleanup

- [ ] (OPS1) [reservations] **Promote Engine-2 (Codex-early draft review + shipit draft-flow) to prod/master** — detectors are already on prod via #1128; this completes the prevention system on `master`. Dependency: the Engine-2 commits edit `codex-auto-request.yml` / `claude-auto-review.yml` / `REVIEWS.md`, which build on the staging-only "local-first review model" base (commits `30f1e5d4`/`fe9f34ea`) and `REVIEWS.md` is absent on master — so cherry-pick that base to the release branch alongside Engine-2. On staging now (PRs #1120 / #1122 merged).

## ✅ Done (recent)
<!-- move completed items here with a date; prune periodically -->
