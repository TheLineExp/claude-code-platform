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
- FR IDs are a single shared sequence across all repos. Next free ID: **FR-049**.

---

## Open Requests

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
