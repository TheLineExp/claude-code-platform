<!-- UNIFIED cross-repo FEATURE backlog. Maintained by the /feature skill (~/.claude/skills/feature/SKILL.md).
     Spans ALL FleetManager repos: reservations / FM V3 / vouchers / azure-ops.
     This file lives in the claude-code-platform repo (backlog/FEATURES.md) and is git-synced
     across every dev machine. The /feature skill pulls before reading and commits+pushes after writing.
     SCOPE: LARGE, undefined feature projects — net-new capabilities or redesigns that need
     scoping/design before they can be built (typically multi-PR). Distinct from /todo (small,
     well-defined quality-sweep fixes/tweaks/ops).
     Item format:  ### FR-NNN: Title   with a **Repo(s)/area** tag.
     ID scheme: FR-### is a single cross-repo sequence; keep IDs stable, never renumber.
     Status: open | under-review | incorporated | declined. -->

# 🚀 Feature Backlog — cross-repo (reservations / FM V3 / vouchers / azure)

_Unified, cross-repo, cross-machine. Synced via `claude-code-platform/backlog/FEATURES.md`._
_Migrated from `fleetmanager-reservations/docs/FEATURE_REQUESTS.md` on 2026-06-16 — full pre-migration detail for incorporated items remains in that repo's git history (`git log -p docs/FEATURE_REQUESTS.md`)._

## How this works
- Add with `/feature add <description>` (size-checked — small/defined work goes to `/todo`).
- Every request carries a **Repo(s)/area** tag so the cross-repo list stays scannable.
- `/feature review` re-prioritizes and checks whether items should move to a repo's `MASTER_PLAN.md` or down to `/todo`.
- FR IDs are a single shared sequence across all repos. Next free ID: **FR-059**.

---

## Open Requests

"### FR-058: Rental-length controls — per-fleet max rental days + Month block toggle
**Repo(s)/area:** reservations (backend + public flow) + FM V3 (admin) · pricing/booking-policy

**Why:** Today `month` is only a price *cap* applied in `pricingResolver.computeMultiDayBikePrice` (`Math.min(total, month)`), NOT a duration a customer picks, and there is **no maximum rental length** — so a customer can already book 30/60/90 days via the multi-day picker (the month rate just caps the price). Owner: "we don't want to rent bikes for months at a time," and wants Month controllable like the other pricing types. (Surfaced verifying PR-8c-3b on staging, 2026-06-24.)

**Scope (per-fleet, owner-confirmed):**
- **Part A — Max rental length.** New `BookingFieldConfig.maxRentalDays Int?` (null = unlimited; migration). Admin input in FM V3 FieldConfigSettings. Public multi-day picker clamps week-chips + day-stepper to `min(maxRentalDays, advanceBookingDays)` + "max N days" hint (DatesSection.jsx). Backend commit gate in `reservationService.createReservation` rejects non-staff multi_day bookings whose inclusive day-count > maxRentalDays (mirror `assertBlockEnabled` placement + `effectiveSource !== 'staff'` bypass). Public GET `/fleet/:id/booking-field-config` already returns the row — add the default.
- **Part B — Month toggle.** FM V3 PricingSettings: add `month` to the matrix enable/disable toggles (default-on; EXEMPT from the enable↔price guard since a cap with no rate = no cap). Gate the month cap on `isBlockEnabled(cfg,'month')` at all 5 `computeMultiDayBikePrice` callers (catalog ×2, availability/v2 ×2, _calculatePricing ×1).

**Build:** PR-A (reservations: schema/migration + admin PUT validate + public GET + commit gate + public-FE clamp + month-cap gating) → deploy (migration) → PR-B (FM V3: maxRentalDays input + month toggle). Status: open → building 2026-06-24 (worktrees `-x18` reservations / FM V3 TBD).


### FR-056: VoloPass reserved→used lifecycle — two-phase hold + redeem-at-cancellation-deadline + payment queue
- **Repo(s)/area**: cross-repo — vouchers (status model + service endpoints) + reservations (reserve/redeem/release triggers + sweep job) + FM V3 (reserved-vs-used display)
- **Status**: open
- **Priority**: P2 (the immediate dropped-pass incident is fixed by PR #1183; this is the proper lifecycle the customer flow implies)
- **Phase-fit**: new cross-repo phase — VoloPass lifecycle. Builds on the existing `voucherService` (validate/redeem/release) + `paymentCaptureJob`/`cancellationPolicyService` patterns.
- **Requested**: 2026-06-22
- **Source**: LINE-HGE5H4 public pass-link incident (`/pass/THEL2606107632` booked full price, un-redeemed). PR #1183 fixed the binding + fail-closed; this FR is the lifecycle the user described. Plan: `~/.claude/plans/witty-splashing-book.md` Part 2.
- **Description**: Today Vouchers is single-phase (`available → redeemed`, revertible via `release`); there is **no `reserved` state**, **no redeem-at-cancellation-deadline trigger** (redeem fires on confirm), and **redeem does not enqueue payment** (a separate scheduled `invoiceService` sweep does). The user wants a pass **RESERVED** at booking (held, releasable), **REDEEMED + enqueued to the payment/settlement queue** when the booking passes its free-cancellation deadline, and the reservation + Vouchers portal to **show reserved-then-used**.
- **Recommended design**: true two-phase hold in Vouchers — add a `reserved` status + `/api/service/reserve` (and convert `/redeem`, `/release`) so `available → reserved → redeemed` (`vouchers/backend/prisma/schema.prisma` status enum, `routes/service.js`, `services/voucherService.js`; portal "reserved vs used" keys on status in `routes/partner.js`). Reservations **reserves** at booking, **redeems** via a scheduled sweep modeled on `paymentCaptureJob` (deadline = `startTime − freeCancelHours` from `cancellationPolicyService`), **releases** on cancel-before-deadline (the cancel-release path already exists at `reservationService.js` ~2477). Surface "Reserved"/"Used" on the reservation (extends the PR-B/PR-C display work) and enqueue the redeemed pass for settlement.
- **Notes**: Only the two-phase hold both shows "reserved" in the Vouchers **portal** AND avoids double-spending a single-use pass before the deadline (the lighter "redeem-at-booking + release-on-cancel, derive reserved/used in Reservations only" alternative loses the portal state and consumes early). **Folds in the deferred item from PR #1183**: preserve the already-booked discount on a *reprice during a Vouchers outage* (currently degrades to no-discount for that recompute — the `failClosedOnVoucherOutage=false` reprice path); the lifecycle work is the natural home for trusting the persisted `discountAmount` on reprice. Display-only pieces (show the pass + pass-aware payment status) ship first as PR-B (FM V3) / PR-C (reservations public confirmation) independent of this lifecycle.

### FR-055: Refund orchestrator concurrency hardening (pre-existing, surfaced by FR-052 audit)
- **Repo(s)/area**: reservations — `refundOrchestrator` + `paymentCaptureJob` / `paymentService.capturePayment`
- **Status**: open
- **Priority**: P1 (real races reachable in normal operation; NOT introduced by FR-052 — pre-exists on the authorized/capture + cancel path)
- **Phase-fit**: orchestrator hardening; pairs with the system-wide review-process effort. Distinct from FR-052 (the manager-refund feature ships on the captured-booking path, largely clear of these).
- **Requested**: 2026-06-21
- **Source**: Independent adversarial concurrency audit during the FR-052 ship.
- **Description**: The refund lock is a non-atomic status-column sentinel (`paymentStatus='refunding'`). Audit found: (P1) the **capture job + `capturePayment` write `paymentStatus:'captured'` with no status guard**, so they can clobber the `'refunding'` sentinel → broken lock / double refund cycle; (P1) the **Stripe op is chosen from the caller's stale `entity.paymentStatus` snapshot**, not the value read under the lock → an authorized→captured race voids an already-captured PI; (P2) the stripe-path final status write is an unguarded `update` (can overwrite a concurrent winner); (P2) **no reaper** for rows stranded in `'refunding'` by a crash mid-refund (lock never auto-releases; Stripe refund with no ledger row).
- **Notes**: Durable fix = atomic acquire (`SELECT … FOR UPDATE` in a `$transaction`, capturing prior status atomically — repo precedent in `groupService`/`customDomainService`) + **status-guard every `paymentStatus` writer** (the one change that actually stops the capture-clobber class) + branch on the lock-read status, not the snapshot + a persisted refund-attempt id as the idempotency anchor (DB-unique ledger dedup) + a `'refunding'`-strand reaper job. The external Stripe/voucher call can't sit inside a DB tx, so the sentinel-across-async-work + idempotency keys + reaper are inherent. Full audit in this session's transcript.

### FR-054: Multiple-Revision Mode for Container Apps Prod Deploys — Zero-Downtime Blue-Green + Version Testing
- **Repo(s)/area**: azure / cross-repo — `deploy.yml` shared pattern across FM V3, reservations, vouchers (all `Single`-revision today)
- **Status**: open
- **Priority**: P1 (every prod deploy currently causes a brief user-facing outage)
- **Phase-fit**: new phase — deploy/infra hardening (azure-ops). Builds on the existing custom-domain-binding guard in `deploy.yml`.
- **Requested**: 2026-06-20
- **Source**: Prod incident 2026-06-20 — FM V3 web-prod 404'd during the PR #1061 deploy. Root cause: in-place `az containerapp update --image` swap in `Single` revision mode has no traffic overlap, so the ingress returns 404/503 for ~30–60s until the new revision is Healthy. minReplicas=1, so not scale-to-zero; binding stayed intact (not the 2026-05-21 failure mode).
- **Description**: Move the prod container apps to **`Multiple` active-revisions mode** and change the deploy to a true blue-green cutover: bring the new revision up at **0% traffic**, wait until it reports Healthy (and optionally smoke-test it via its direct revision FQDN / a `--revision-suffix` label), then **shift 100% traffic** to it and retire the old revision. Eliminates the per-deploy 404 window AND unlocks **version testing in prod** — a new revision can be validated on a labeled URL (or canary traffic split, e.g. 90/10) before promotion, and rollback becomes an instant traffic re-point to the prior healthy revision instead of a redeploy.
- **Notes**: Cross-repo — the same `deploy.yml` pattern lives in all three repos, so design once and roll out consistently (FM V3 first as the pilot). Touch points: revision-mode config, `--revision-suffix` naming (e.g. git SHA), traffic-split commands, the post-deploy health check (must target the *new* revision's label, not just the app FQDN, or it can pass against the old revision), and the DB-migration step ordering (migrations must be backward-compatible with the still-live old revision during overlap — expand/contract). Cheaper interim mitigations if this slips: bump `minReplicas` to ≥2, or add a readiness probe to narrow the swap window. Pairs with the existing custom-domain-binding guard.

### FR-053: Server-authoritative "early-pickup available?" signal for the public booking flow
- **Repo(s)/area**: reservations — backend (availability/pricing preview) + public FE (`useDateSelection.js`)
- **Status**: open
- **Priority**: P2 (raise to P1 before enabling `earlyPickupEnabled` broadly in prod)
- **Phase-fit**: hardening follow-up to the shipped early-pickup generalization (PRs #1086/#1088/#1091/#1094); not a new phase. Related to **FR-039** (admin dates-step early-pickup/late-dropoff) but distinct surface (this is the public customer flow + the FE/BE source-of-truth).
- **Requested**: 2026-06-20
- **Source**: Recurring Codex/Claude review findings across the early-pickup PRs.
- **Description**: The FE optimistically re-derives early-pickup eligibility (`earlyPickupInfo` / `earlyPickupAvailWindow` in `useDateSelection.js`) while the backend `_resolveEarlyPickup` is authoritative and declines in cases the FE can't fully mirror without a server call — scoped/event-link flows, a `BlockoutDate` on the prior evening, after-close, in-grace, no-next-open-morning, etc. Each gap is a preview/charge mismatch (the card + fee show, the server drops them) that's been patched one-at-a-time (Codex #84/#88/#91/#92/#133/#136/#139 + the P1 scoped-shift). Replace the optimistic FE derivation with ONE server-authoritative signal: a per-cart "early pickup available?" result (eligible + billed/hold windows + fee), folded into the existing availability or a pricing/preview call, that the FE consumes directly.
- **Notes**: Eliminates the whole mismatch class and prevents future mirror-gaps in one place. The remaining accepted edge case (#136 — blockout on the exact prior evening degrades to a morning pickup, no overcharge) closes for free once the FE no longer offers what the server will decline. Pairs with `/todo` FF1 (surface the same-day shift in the public slot builders). **Recommend building this before turning on `earlyPickupEnabled` for production locations.**

### FR-052: Manager "Issue Refund Anytime" — Credit-First Refunds Without Cancelling
- **Repo(s)/area**: cross-repo — reservations (payments/refunds) backend + FM V3 admin UI
- **Status**: ✅ **SHIPPED to prod 2026-06-21** (reservations #1097→master + FM V3 #1063 UI + #1071 UI-fixes→main; both prod deploys green + health ok). Manager "Issue Refund Anytime" (credit-first, idempotent, rounds 1-5 fixes) live, backend + UI consistent. Took 5 Codex review rounds — recurring concurrency/interaction misses drove the system-wide review-process effort (separate window). **Follow-ups:** FR-055 (pre-existing orchestrator concurrency hardening — atomic lock, capture-clobber guard, reaper); post-prod convergence back-merges (master→staging, main→staging) + FR-052 worktree/branch cleanup still to run. Prod PRs: [reservations#1097](https://github.com/TheLineExp/fleetmanager-reservations/pull/1097) → master + [Fleetmanager_V3#1063](https://github.com/TheLineExp/Fleetmanager_V3/pull/1063) → main. Codex's full-diff pass on those prod PRs found **7 more real issues** (2 concurrency P2s — idempotency TOCTOU + stale-aggregate over-issue; a confirm-gate regression from the awaitingPayment fix; require-key; sanitize; docstring; FM V3 credit-default-on-completed). Fixes on staging: **[reservations#1104](https://github.com/TheLineExp/fleetmanager-reservations/pull/1104)** (6, 163 tests green) + **[Fleetmanager_V3#1067](https://github.com/TheLineExp/Fleetmanager_V3/pull/1067)** (credit-default live-only, 22 green). **Next: merge #1104 + #1067 to staging → cherry-pick the fix commits onto the prod release branches (updates #1097/#1063) → merge the two prod PRs together.** Then back-merge master→staging + main→staging, then worktree cleanup.
- **Priority**: high
- **Phase-fit**: Extends the shipped **Unified Refund System** (reservations `refundOrchestrator`, P0.5, shipped 2026-04-13) and the **F1 Rental Credit / Goodwill voucher** work (vouchers PR #70). Likely a small reservations refund sub-phase + a paired FM V3 frontend chunk — not a new phase.
- **Requested**: 2026-06-19
- **Source**: Owner request — a manager should be able to issue partial or full refunds at **any point**, not only after cancelling. Real scenarios: **bike damage, injury** mid-rental, where the booking should stand (not be cancelled) but the customer needs compensating.
- **Description**: One unified manager **"Issue Refund"** action available on **active / confirmed / completed** reservations (not just `completed`, and without forcing a cancellation). **Defaults to store credit**, with a toggle to **refund to the original card** or record **cash**. Both credit and card are *real refunds* recorded against the booking (voucher_credit uses `programType:'refund'`, distinct from the existing goodwill comp). Partial and full amounts supported.
- **Notes**:
  - **Engine already exists** — `refundOrchestrator.processRefund()` supports `mode:'post_rental'` (gives money back without touching reservation status), all three methods (stripe / cash / voucher_credit), partial amounts, locking, audit, reconciliation, and customer notifications. `voucherService.issueCredit` already distinguishes `programType:'refund'` (real refund as credit) vs `'goodwill'`. **The work is opening the door + defaulting to credit, not building refund logic.**
  - **Backend (reservations)**: new `reservationService.issueRefund()` generalizing the completed-only `postRentalRefund` ([reservationService.js:3343]); allow status ∈ active/confirmed/completed; default `refundMethod='voucher_credit'`; auto-build voucherCredit `programName`/1-yr expiry; `releaseVoucher=false`. Repurpose `POST /api/reservations/:id/refund` ([reservations.js:575]) to call it, manager-gated, keep `requireFreshPin`. Keep Stripe's 180-day hard cap (beyond it → credit/cash only). Window guard (`computePostRentalPolicy`) applies only to the `completed` case and is override-gated; no window for active/confirmed. Add `bike_damage` + `injury` to `INTERNAL_REFUND_REASONS` ([paymentService.js:29]) + customer-safe text. No schema migration.
  - **FM V3 (frontend, separate repo)**: new `IssueRefundModal` + `useIssueRefund()` hook in `frontend/src/pages/reservations/` (alongside `CancelRefundModal`/`IssueCreditModal`); amount (default max refundable, partial allowed), method selector **defaulting to Store credit** (Card / Cash options), reason select (+ new reasons), note, override + attestation when over policy/window; disable Card with inline reason when no capture or past 180 days.
  - **Vouchers**: no change — `programType:'refund'` propagation already shipped (PR #70, 2026-05-07); verify live in target env before build.
  - **Accounting**: a voucher_credit refund writes a `type:'refund'` Payment row but does NOT reduce the card capture's `refundedAmount` (no card money moved); stripe reduces both; goodwill credits stay off the refund ledger.
  - **Decision (2026-06-19)**: credit-first = real-refund-paid-as-credit (not goodwill comp); available on active/confirmed/completed only (not cancelled/no_show); **plan both repos, build together** — coding held until FM V3 is checked out alongside reservations.
  - **Cross-check / overlap**: FR-036 (early-return refund on check-in time adjustments) and FR-037 (breakage hold & damage charge) are damage/refund-adjacent — coordinate so damage flows can hook this refund path rather than duplicate it.

### FR-051: Employee Discounts & Customer Types — Standing Special-Pricing Tiers
- **Repo(s)/area**: reservations (pricing) + FM V3 admin UI
- **Status**: open
- **Priority**: medium
- **Phase-fit**: Extends the pricing/discount area (per-bike-type pricing, discount codes, VoloPass, manager price override) — likely a new "pricing tiers / customer segments" sub-phase rather than folding into an existing one.
- **Requested**: 2026-06-18
- **Description**: Support **customer types / segments** (e.g. member, VIP, corporate, local, repeat) that carry **standing special pricing** applied automatically at booking, plus an **employee discount** mechanism (staff comp or % off). Today pricing is per-bike-type with optional discount **codes** / VoloPass redemption + a one-off manager **price override**; there is no concept of a customer category that always prices differently, nor a built-in employee/comp rate — staff hand-apply overrides each time.
- **Notes**:
  - **Needs design** before build — open questions: where the type lives (tag on `Customer`, or chosen per booking?), how pricing rules attach to a type (flat % off / fixed tier table / per-bike-type multiplier), how employees are identified (FM staff account vs a redeemable employee code), and precedence/stacking vs existing **discount codes / VoloPass / tax-exempt**.
  - **Blast radius**: pricing calc (`_calculatePricing`), `Customer` model + admin customer UI, booking flow (auto-apply at quote time), FM V3 PaymentSection / discount entry points, reporting (segment revenue).
  - **Cross-check**: existing discount-code + VoloPass infra (could the "type" just be an auto-applied, non-consuming discount?) and the manager price-override path (x42).

### FR-050: Group Balance Collection — One Payment Link for a Group's Adjusted Remainder
- **Repo(s)/area**: reservations (payments) + FM V3 PaymentSection UI
- **Status**: open
- **Priority**: medium
- **Phase-fit**: Extends the staff payments/charge area (PaymentSection, manager price override, Send Payment Link) — new reservations payments sub-phase, or folds into the group-booking phase.
- **Requested**: 2026-06-18
- **Source**: 2026-06-18 LINE-ERWQVM incident — a group (group `366372de`) of **4 reservations** ($249.32 + $136.44 + $96.44 + $74.60 = **$556.80**), only **$103.74** ever paid (one charge on the leader), no saved card. Staff needed to re-price for all bikes (one bike 50% off), credit the $103.74, and send the customer **one** link for the remainder — and there was no way to do it.
- **Description**: A **group-level "collect remaining balance"** flow: sum the group's *adjusted* totals across all member reservations (respecting per-bike price overrides + discounts), subtract everything already paid across the group, and mint **ONE** Stripe Checkout link for the net remainder — then reconcile each member reservation's `paymentStatus` when the link is paid.
- **Notes**:
  - **Why it's hard today**: both collection paths are **per-reservation** — `_settleReservationDelta` / `createUpgradePaymentLink` and the FM V3 Send-Payment-Link button all operate on a single reservation, so a group whose bikes are split across N reservations can't be billed in one go. `getGroupTotal()` already sums member totals; the legacy `markGroupPaid` (aggregate group_payment row) is retired and shouldn't be revived as-is (it caused the double-count display issues this incident surfaced).
  - **Design questions**: which reservation "owns" the link (leader?), how the paid amount is split/recorded back across members, how it interacts with the now-per-seat group payment model, and group-vs-member status reconciliation on `checkout.session.completed`.
  - **Interim workaround used**: a manual Stripe Dashboard Payment Link (or a single `createUpgradePaymentLink` on the leader) for the exact remainder, with manual status cleanup.


### FR-048: Fleet Manager Staff Native Mobile App (iOS + Android, Expo)
- **Repo(s)/area**: cross-repo — new `fleetmanager-mobile` (Expo) + FM V3 backend + reservations backend
- **Status**: open (in progress — C0 done)
- **Priority**: high
- **Phase-fit**: New product line / new repo with its own `docs/MASTER_PLAN.md` (chunks C0–C7). Not part of an existing repo's phase plan.
- **Requested**: 2026-06-16
- **Description**: Native iOS + Android app for fleet **staff** (managers + employees). Phase 1 = the daily field loop: login, bike barcode/QR scan & lookup, check-in/out (GPS + damage photos), safety inspections — **plus** staff-side reservation management: view upcoming/current reservations, start & stop a rental, swap bikes, create a reservation, and sign waivers. Public self-serve booking stays browser-based (low-frequency public use doesn't justify an app). The app doubles as a public distribution/visibility surface for the larger system.
- **Notes**:
  - **Repo created**: `Volo Technologies/fleetmanager-mobile` (org `TheLineExp`). Skeleton chunk **C0 committed** — Expo SDK 56 + TS + expo-router; dual-base-URL axios client (`fmApi` + `reservationsApi`) sharing the FM JWT; `expo-secure-store` tokens; TanStack Query + MMKV offline cache; Zustand auth store mirroring FM role selectors. Plan: `fleetmanager-mobile/docs/MASTER_PLAN.md`.
  - **One token, two backends**: both FM V3 and reservations verify the same JWT (`issuer fm-vouchers`, `aud fm-staff`). Reservation start/stop **bridges** into FM check-out/check-in (`reservations/:id/start mode=with_checkout` → FM `/checkouts`) — no client-side reconciliation.
  - **Backend work needed (the only net-new server work)** — FM V3: native Google OAuth deep-link callback returning tokens (`fleetmanager://auth?token=…`); `DeviceToken` table + register/unregister endpoints + Expo push dispatch on existing notification triggers and reservation events. Reservations: verify `Idempotency-Key` honored on the **staff** create route + FM `/checkouts` retry-safety (backbone of offline replay).
  - **Decisions**: offline = queued writes + cached reads; devices = hybrid (personal phones + shared **PIN kiosk** fast-switch — infra already exists); Stripe Terminal deferred (Phase 1 uses payment links / pay-at-pickup); distribution = **public Apple App Store + Google Play** (internal TestFlight/Play tracks first).
  - **Next**: C1 — auth & roles (email/Google/PIN), refresh interceptor, fleet picker, role-gated nav.

### FR-047: Fleet/Reservation Onboarding Wizard — Required Defaults + Go-Live Gating
- **Repo(s)/area**: reservations (+ FM V3 settings UI)
- **Status**: open
- **Priority**: high
- **Phase-fit**: Extends Phase 16B (FR-020 "Guided Tenant Onboarding", already incorporated) — adds **required-field completion gating** + a comms/policy default set, rather than a fresh phase. Could land as 16B.2.
- **Requested**: 2026-06-05
- **Source**: 2026-06-05 production incident (x27) — customer reservation emails/SMS were showing the **internal fleet manager's** contact (DJ) instead of the shop's. Root cause: Reservations has no admin surface to set a customer-facing support contact, so every customer-facing builder fell back to FM `Fleet.contactEmail`/`contactPhone` (the fleet's internal contact). x27 fixes the leak (removes the FM fallback in customer comms + adds a Support Email/Phone settings field), but the deeper gap is that **nothing forces a fleet to supply a complete, correct set of customer-facing defaults before going live** — so the system guesses, and guessing leaks internal data.
- **Description**: Build a guided, multi-step onboarding wizard that collects every piece of data the Reservations system needs to operate a fleet safely, writes them as the fleet's defaults, and **gates go-live on a complete required set** so customer-facing surfaces never fall back to internal FM data. Steps (draft):
  1. **Identity & branding** — fleet display name, slug, logo, colors, browser title.
  2. **Customer-facing communications (REQUIRED)** — support email, support phone, SMS from-name, email footer text. These are the fields whose absence caused the x27 leak; require at least email + phone before go-live.
  3. **Locations** — name, address, timezone, coordinates, business hours for each bookable location.
  4. **Policies (REQUIRED)** — cancellation policy (free-cancel window + late-cancel fee), rental policies, pickup buffer, no-show grace, waiver requirement.
  5. **Notification channels** — which channels are enabled (SMS/email), provider config (Resend/ClickSend) or confirm the platform default, quiet hours.
  6. **Booking config** — duration types offered, advance-booking rules, deposit/payment mode.
  7. **Review & activate** — show a completeness checklist; block "Go Live" until all REQUIRED fields are set; surface exactly what's missing.
- **Notes**:
  - **Anti-pattern to kill**: silent fallbacks to FM `Fleet.contactEmail`/`contactPhone`/`name` in any customer-facing path. The wizard's job is to make the Reservations-side values authoritative and present, so fallbacks are never reached. (See x27 / `reservationContentService`, `reservationNotificationService`, `paymentFailureNotifier`.)
  - **Overlap with FR-020 (Phase 16B, incorporated)**: FR-020 was "guided tenant onboarding" generically. This FR is the concrete, gated, comms-and-policy-complete version motivated by a real leak. Treat FR-047 as the implementation spec / hardening of 16B, not a duplicate — verify what 16B actually shipped before building (it may be partial scaffolding).
  - **Completion gating is the key new idea**: a fleet should not be able to take a public booking until its required comms + policy set is complete. Consider a `TenantConfiguration.onboardingComplete` (or a derived completeness check) that the public booking routes consult, with a clear admin "X of Y required steps remaining" surface.
  - **Cross-repo**: the wizard UI lives in FM V3 (reservations settings), backed by Reservations admin endpoints (most config columns already exist on `TenantConfiguration`/`TenantBranding`/`LocationSettings`; the gap is write endpoints + a required-set validator). x27 adds the first missing write path (support email/phone); the wizard generalizes it.
  - **Defaults vs required**: collect everything, but only HARD-require the set whose absence is customer-visible or legally meaningful (support contact, cancellation policy, waiver, timezone). Soft-default the rest (colors, footer copy) with sensible platform values.
  - Should also retro-fill: a one-time audit/checklist for already-live fleets (The Line) so existing tenants are brought up to a complete required set, not just new ones.

### FR-046: Reservations Staging-Refresh — Daily prod→staging DB Sync
- **Repo(s)/area**: reservations (devops / staging infra)
- **Status**: open
- **Priority**: low
- **Phase-fit**: New phase (devops / staging infra) — analogous to FM V3's `.github/workflows/staging-refresh.yml`, but Reservations-side
- **Requested**: 2026-05-24
- **Source**: 2026-05-24 incident — admin reservation creation on staging failed with "Database operation failed" because 7 of 11 The Line bike types had `PricingRule.bikeType` names that drifted from FM's canonical `BikeType.name` registry (e.g. "Full Suspension Mountain Bike" rule vs "Full Suspension" FM type, missing "E-Hardtail Mountain Bike" entirely). Public availability/v2 hid 7 types from customers; admin "New Reservation" couldn't price them. Fixed in-conversation via manual SQL (6 UPDATEs renaming + 3 INSERTs for E-Hardtail, prices pulled from prod's `/availability/v2`). The deeper problem: there's no mechanism to detect this drift, so it accumulates silently and surfaces only when someone tests an unpriced bike type.
- **Description**: Build a daily prod→staging Reservations DB sync that mirrors `fleetmanager_reservations` from `reservations-db-prod` into `fleetmanager-db-staging`. Same pattern as FM V3's `staging-refresh.yml` (scheduled GitHub Action, `pg_dump | pg_restore --no-owner --no-acl`, re-apply GRANTs, snapshot/restore environment-specific overrides). Eliminates the "staging diverges from prod over time" failure mode for ALL Reservations tables, not just pricing.
- **Notes**:
  - **Cross-server pg_dump | pg_restore** required (unlike FM V3 which dumps and restores on the same server). Prod is on dedicated `reservations-db-prod`, staging is on shared `fleetmanager-db-staging`. Workflow needs both connection strings as secrets.
  - **Environment-specific overrides to snapshot/restore around the dump**: audit before shipping — there may be nothing actually needing snapshot/restore.
  - **PII concerns**: prod has real customer PII (encrypted). Two paths: (A) share encryption keys between prod and staging (simpler, security trade-off), (B) strip/anonymize Customer + Waiver + ReservationLog during restore (preferred). Decision required before building.
  - **Cadence**: daily at 4 AM UTC matches FM V3. Container restart needed after to clear caches.
  - **Sequencing with FM refresh**: must run AFTER FM's so the `reservations_reader` GRANT re-application finishes first.
  - **Connection-storm interaction**: account for the connection-pool budget (P2037 "too many connections" bit staging 2026-05-24).
  - User priority note: "post-launch cleanup, not urgent."

### FR-045: Food Pre-Orders — Menu Add-Ons from 3rd-Party Provider (Aeret / etc.)
- **Repo(s)/area**: reservations (+ FM V3 admin), vendor integration
- **Status**: open
- **Priority**: medium
- **Phase-fit**: Configurator Phase 3E extension (Add-Ons system) + likely a new sub-phase for vendor integration — first round can ship as a manual menu without 3rd-party API
- **Requested**: 2026-05-23
- **Description**: Let riders pre-order food alongside their bike reservation, with pickup at the location when they collect their bikes. Phase 1 is a "deferred payment / pay at pickup" model — no Stripe charge for food at booking time. Two ways to populate the menu: (1) **Manual menu items** in the configurator (name, description, price, photo, category, availability) tagged "food / consumable" with a vendor reference; (2) **Import from vendor web page** (e.g., Aeret café at The Line). At checkout the public flow surfaces an "Add food to your ride?" step; the order attaches to the reservation and shows on the fleet's pickup screen.
- **Notes**:
  - Treat the vendor as configurable from day one so other fleets can plug in their own provider.
  - **Phase 1 (MVP)**: Menu CRUD + reservation attachment + staff pickup view. No Stripe, no inventory, no vendor API.
  - **Phase 2 (paid pre-orders)**: charge food via existing Stripe (19A/19B); Stripe Connect transfer if vendor is a separate account (like vouchers `webhook → transfer`).
  - **Phase 3 (vendor API)**: push to POS (Square/Toast/Clover) if available.
  - **Phase 4 (live menu sync)**: real-time availability.
  - Overlap with FR-042 (water bottles + Lightspeed): both are "consumable add-ons sold alongside a reservation." Shared "ConsumableAddOn" model with a `vendor` field (`internal-lightspeed` vs `external-<vendorName>`).
  - Food orders should respect the **bike pickup time**, not "now". Edge cases: modify/cancel reservation → food follows; walk-in (FR-035) → shorter prep window; multi-bike group → per-reservation line items.
  - Revenue/stickiness play even at zero food margin; opens commission/referral conversations.

### FR-044: "No Minimum Notice" Toggle on Rental Policies
- **Repo(s)/area**: reservations (Configurator — rental policies admin)
- **Status**: open (reopened 2026-05-24 — prior audit was wrong)
- **Priority**: medium
- **Phase-fit**: Configurator (rental policies admin) — small additive setting on existing per-fleet/per-location booking config
- **Requested**: 2026-05-08
- **Source**: BUG-1778201111337-i21e2f (May 8, 2026, prod) — fleet operator requested "No minimum notice to book".
- **Audit note (2026-05-24, corrected)**: An earlier audit (PR #476, `bc5a0d3`) wrongly moved this to Incorporated claiming walk-in mode bypasses the min-notice gate. The walk-in plumbing (`reservationService._shouldSkipBuffer`) only skips the back-to-back BUFFER gap, not the min-notice gate. The min-notice gate at `availabilityService.validateBusinessHours` (lines 184-192) fires for ALL sources with no `source`/`isWalkIn` exemption, and `createReservation` calls it BEFORE the walk-in source check. **Options**: (a) add `source`/`isWalkIn` exemption to `validateBusinessHours`, (b) expose `LocationSettings.minBookingNotice` in admin UI (column already exists — lowest risk), or (c) add a `noMinimumNotice` boolean. **Lesson captured in memory**: code-verification on multi-gate flows must trace each gate individually.
- **Description**: Add a fleet (or location) setting allowing bookings up to "right now" — no minimum-notice / lead-time gate. Overlaps FR-035 (walk-in instant rental, incorporated); FR-044 is the missing piece that lets fleets actually set `minBookingNotice=0`.
- **Notes**: per-location `LocationSettings.minBookingNotice` naturally handles per-location rules; public date/time picker should reflect the toggle (show "now" as earliest selectable).

### FR-043: Bulk Booking — Replace Bike Size with Rider Height + Auto-Pick
- **Repo(s)/area**: FM V3 (bulk booking UI) + reservations (size engine, already shipped)
- **Status**: open (scope confirmed 2026-05-24 — engine + endpoint SHIPPED, bulk-flow wiring still open)
- **Priority**: medium
- **Phase-fit**: Phase 18A (extends guided-booking recommendation engine into the bulk/group flow)
- **Requested**: 2026-05-08
- **Source**: BUG-1778199493442-xi2c3d (May 8, 2026, prod) — "Remove bike size from Bulk Booking, replace with height to auto-calculate the correct bike size (and bike) per rider".
- **Audit note (2026-05-24)**: Engine + endpoint SHIPPED — `sizeRecommendationService.getRecommendation(fleetId, bikeType, heightCm)` via `GET /public/fleet/:fleetId/size-recommendation`; FM V3 single-rider staff form consumes it (FR-040). NOT built: bulk-flow wiring. `BulkBookingPage.jsx` still uses a manual `bikeSize` CSV column; bulk endpoint `POST /api/admin/:fleetId/reservations/bulk` reads `bikeSize` directly. Remaining: add `height` column to CSV/table UI, wire `sizeRecommendationService` into the bulk endpoint (or pre-resolve per row), keep manual size as override.
- **Notes**: keep size as an editable override; warn "no <size> available, picked closest match" rather than silently downgrading.

### FR-042: Water Bottles & Consumable Add-Ons + Lightspeed Inventory Sync
- **Repo(s)/area**: reservations (Add-Ons + Lightspeed POS integration)
- **Status**: open (scope confirmed 2026-05-23 — base Add-Ons SHIPPED, extension still open)
- **Priority**: medium
- **Phase-fit**: Phase 10F (extends Lightspeed POS integration FR-013) + Configurator Phase 3E (extends FR-028)
- **Requested**: 2026-05-07
- **Source**: BUG-1777237080752-19vmbi (Apr 26, staging) — "Can we add water bottles as Add-Ons and connect inventory to Lightspeed?"
- **Audit note (2026-05-23)**: Base Add-Ons SHIPPED via Configurator 3E (FR-028) — admin can create AddOns with `equipmentTypeId`, `inventoryMode`, `maxQuantity`. NOT built: `isConsumable` flag, `stockOnHand` counter, `lightspeedItemId` link, and the Lightspeed sync (Phase 10F not started). This FR remains scoped to the consumable + Lightspeed extension.
- **Description**: Extend Add-Ons to support **consumable retail items** (water bottles, bars, tubes) with `stockOnHand`, synced bidirectionally with **Lightspeed POS** so a reservations sale decrements the same stock the storefront sees.
- **Notes**: depends on FR-013 Lightspeed integration landing first; could ship local consumable inventory tracking sooner as a 10F precursor.

### FR-039: Admin Dates Step — Early Pickup / Late Dropoff + Intuitive Duration UI
- **Repo(s)/area**: FM V3 (admin booking flow — ReservationForm DatesStep)
- **Status**: open (scope narrowed 2026-05-23 — duration types SHIPPED)
- **Priority**: medium
- **Phase-fit**: New sub-phase or Configurator extension (admin booking flow)
- **Requested**: 2026-03-12
- **Related**: FR-036 (late/early return pricing), public DatesSection.jsx, useDateSelection hook
- **Scope-narrowing note (2026-05-23)**: Duration-type plumbing SHIPPED — `DatesStep.jsx` + `ScheduleEditor` support all 5 duration types; `BulkBookingPage.jsx` enumerates the same five. NOT built: (1) explicit early-pickup / late-dropoff toggle UI on the staff dates step, (2) reuse of public `useDateSelection`/`CalendarPicker` controls in the staff form.
- **Description**: Overhaul the admin "Dates" step to support early pickup (day before) and late dropoff (day after) with a duration-aware UI matching the public flow. Early/late toggles primarily for Full Day + Multi-Day. Reuse public flow patterns (`useDateSelection`, `CalendarPicker`) over rebuild.
- **Notes**: current admin step `frontend/src/components/ReservationForm.jsx`; promote `CalendarPicker` to a shared component; show pricing impact if FR-036 lands.

### FR-037: Breakage Hold & Damage Charge — Stripe Card Hold + Work Order Debit
- **Repo(s)/area**: reservations + FM V3 (damage UI) — Stripe + SP work orders
- **Status**: open (scope narrowed 2026-05-23)
- **Priority**: medium
- **Phase-fit**: Phase 19 (extends Stripe 19A preauth + 19B PaymentSection) + Phase 20 (SP work orders via FR-003)
- **Requested**: 2026-03-11
- **Related**: Phase 19A/19B, FR-003 (SP work orders), FR-028 (Damage Waiver), Returns flow
- **Scope-narrowing note (2026-05-23)**: Damage attribution + immediate charge SHIPPED (x4 unified damage bridge + x5 timestamp-based renter attribution; `damageChargeService.js`, FM V3 `DamageChargeDetail.jsx`). NOT shipped: the two-stage **Stripe card HOLD** (`PaymentIntent` `capture_method: 'manual'`). Today `damageChargeService.chargeCustomer()` uses `confirm: true` (immediate off-session). Remaining: convert/add a hold-then-capture flow so funds are secured during assessment before the cost is known.
- **Description**: Flag breakage at check-in → place a Stripe authorization hold on the saved card → create a damage estimate → on work-order finalization, capture actual cost (partial/full/+difference). Waiver (FR-028) coverage applied before charging. Per-fleet config: `breakageHoldEnabled`, `breakageMaxHoldAmount` ($500 default), `breakageHoldDuration` (7d), `breakageNotifyCustomer`, `breakageDisputeWindowDays`.
- **Notes**: requires saved card (19A); holds expire after 7 days; new models `DamageClaim` + `DamageClaimLineItem`; edge cases — cash-at-pickup (no card), multi-bike reservation.

### FR-036: Check-In Time Adjustments — Late Return Surcharge & Early Return Refund
- **Repo(s)/area**: reservations (payment/pricing — Returns flow)
- **Status**: open (scope narrowed 2026-05-23 — late surcharge half SHIPPED)
- **Priority**: medium
- **Phase-fit**: Phase 19 (extends 19A Stripe + 19B PaymentSection)
- **Requested**: 2026-03-11
- **Related**: Phase 19A/19B/19C, Returns flow
- **Scope-narrowing note (2026-05-23)**: **Late return surcharge SHIPPED** — `reservationService.completeReservation()` calculates `lateFeeAmount` on check-in, applies to `totalAmount`, logs to `staffNotes`; schema has `lateFeeAmount` + `lateFeePerHour`. **Early return pro-rated refund NOT built** — no `earlyReturnRefund` field, no Stripe partial-refund flow at check-in. Remaining: early-return refund flow + config (`earlyReturnPolicy`, `earlyReturnMinCharge`, `earlyReturnMinHours`).
- **Description**: Staff adjust charges at check-in vs scheduled return time. (1) Late surcharge (per-hour/flat/percentage/grace), added to existing Stripe payment — higher priority, shipped. (2) Early-return pro-rated refund (pro-rated/min-charge/none), via Stripe partial refund — remaining. Config keys: `lateReturnPolicy/Rate/GraceMinutes`, `earlyReturnPolicy/MinCharge/MinHours`. All opt-in per fleet (default `none`); staff can override any auto-calc.
- **Notes**: requires card on file (19A); edge cases — cash-at-pickup, group reservations with different return times; feeds Phase 19E reporting.

### FR-027: Gear Manager — Generic Outdoor Gear Platform (FM Fork)
- **Repo(s)/area**: new product (FM fork — separate repo once FM stable)
- **Status**: open
- **Priority**: low
- **Phase-fit**: New product (not a phase — separate fork/repo once FM is stable)
- **Requested**: 2026-02-25
- **Description**: Fork FleetManager into a **Gear Manager** for any outdoor gear (ski/kayak/camping/surf/snowboard/e-scooter). Core fleet/inventory/reservation/booking engine stays; generalize "bike" → "gear item" with configurable gear types, flexible per-category attributes, generalized sizing/fit, category-aware maintenance, gear-agnostic booking, multi-category fleets.
- **Notes**: lower priority / longer term — FM must be solid first. Product fork, not a feature. Two approaches: (A) fork FM, replace bike-specific code; (B) refactor FM itself gear-agnostic (cleaner long-term, riskier). The Reservations plugin is already fairly gear-agnostic. Could be a separate SaaS tier.

<!-- Format: ### FR-NNN: Title  +  **Repo(s)/area** tag -->
<!-- Status: open | under-review | incorporated | declined -->

---

## Under Review

_Features being evaluated for incorporation into a repo's master plan._

---

## Incorporated (archive)

_Migrated from reservations on 2026-06-16. Full original detail preserved in `fleetmanager-reservations` git history — `git log -p docs/FEATURE_REQUESTS.md` and search by FR number._

| ID | Feature | Repo | Incorporated Into | Date |
|----|---------|------|-------------------|------|
| FR-049 | Date-Specific / Holiday Hours Overrides (per-location) | reservations + FM V3 | reservations prod (master) + FM V3 prod (main) — SpecialHours model/migration/enforcement/admin CRUD/public dateOverrides + staff editor | 2026-06-19 |
| FR-001 | SP Workspace — Scoped Data Access + Urgent Alerts | reservations | Phase 9A-9C | 2026-02-21 |
| FR-002 | SP Directory + Geolocation Matching | reservations | Phase 9D | 2026-02-21 |
| FR-003 | SP Billing, Charges, Contracts & Work Orders | reservations | Phase 9E | 2026-02-21 |
| FR-004 | Smart Availability — Substitute Bike & Time Slots | reservations | Phase 13A | 2026-02-21 |
| FR-005 | Inter-Fleet Bike Transfer | reservations | Phase 15B | 2026-02-21 |
| FR-006 | Commission-Based Affiliate Rental Program | reservations | Phase 14A | 2026-02-21 |
| FR-007 | Calendar Week View + Drag-and-Drop Reschedule | reservations | Phase 13B | 2026-02-21 |
| FR-008 | FM Integration Views — Bike Detail & Location | reservations | Phase 13C | 2026-02-21 |
| FR-009 | Experience Finder Questionnaire | reservations | Phase 16D | 2026-02-21 |
| FR-010 | Embeddable Booking Widget | reservations | Phase 14B | 2026-02-21 |
| FR-011 | Cross-Location Bike Transfers & Fleet-Wide Search | reservations | Phase 15A | 2026-02-21 |
| FR-012 | Advanced Group Booking — Invite Friends & Mass | reservations | Phase 14C | 2026-02-21 |
| FR-013 | Lightspeed POS Integration | reservations | Phase 10F | 2026-02-21 |
| FR-014 | Dynamic Pricing Rules Engine | reservations | Phase 10C | 2026-02-21 |
| FR-015 | Voucher System — thelinevouchers | vouchers | Phase 10D | 2026-02-21 |
| FR-016 | Advanced SMS — Two-Way Messaging & Admin Console | reservations | Phase 12C | 2026-02-21 |
| FR-017 | Custom Domains for Public Booking | reservations | Phase 16E | 2026-02-21 |
| FR-018 | Per-Tenant Feature Flags | reservations | Phase 16A | 2026-02-21 |
| FR-019 | Reporting & Analytics Suite (superseded by FR-025) | reservations | Phase 15C | 2026-02-21 |
| FR-020 | Guided Tenant Onboarding | reservations | Phase 16B | 2026-02-21 |
| FR-021 | Extended Rentals & Leases — Recurring Billing | reservations | Phase 16C | 2026-02-21 |
| FR-022 | Corporate Accounts & Monthly Invoicing | reservations | Phase 14D | 2026-02-21 |
| FR-023 | Demo & Premium Bike Rentals — Restricted Availability | reservations | Phase 10C | 2026-02-21 |
| FR-024 | Ikeono SMS — Waivers, Rentals, Payments & Comms | reservations | Phase 12A-12B | 2026-02-21 |
| FR-025 | Cross-System Reporting — Bike, Fleet & System Level | reservations | Phase 19C | 2026-03-02 |
| FR-026 | AI Conversational Booking Agent (Voice + Text) | reservations | Phase 21 | 2026-03-02 |
| FR-028 | Damage Waiver & Configurable Add-Ons/Extras | reservations | Configurator Phase 3E | 2026-03-02 |
| FR-029 | Proxy Booking & Parental Consent | reservations | Phase 13B | 2026-03-02 |
| FR-030 | Self-Service Cancel/Modify/Group Portal | reservations | Phase 13C | 2026-03-02 |
| FR-031 | Confirmation Page — Print, Content, Wallet | reservations | Configurator Phase 6 (6A/6B/6D) | 2026-03-02 |
| FR-032 | Mobile Sticky Continue Button | reservations | Configurator Phase 4 | 2026-03-02 |
| FR-033 | Post-Booking "What's Next" CTAs | reservations | Configurator Phase 6C | 2026-03-02 |
| FR-034 | White-Label Branding — Preset Palettes + Logo Upload | reservations | Active Sprint (Remaining Items) | 2026-03-02 |
| FR-035 | "Book for Right Now" Walk-In Instant Rental | reservations | Configurator Phase 3F | 2026-03-02 |
| FR-038 | Reorder Safety Checklist Items | FM V3 | SafetyTemplateEditor (button-based reorder) | 2026-05-23 |
| FR-040 | Bike Recommendations on Staff `/reservations/new` | FM V3 + reservations | `BikesStep.jsx` `useSizeRecommendation()` → `GET /public/fleet/:id/size-recommendation` | 2026-05-24 |
| FR-041 | "Add Service Issue" Direct Action on Bike Detail | FM V3 | BikeDetail.jsx `+ Add Service Task` + MaintenanceFormModal | 2026-05-23 |

---

## Declined

_Features evaluated and decided against (with reasoning)._

| ID | Feature | Repo | Reason | Date |
|----|---------|------|--------|------|
