<!-- UNIFIED cross-repo FEATURE backlog. Maintained by the /feature skill (~/.claude/skills/feature/SKILL.md).
     Spans ALL FleetManager repos: reservations / FM V3 / vouchers.
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
- FR IDs are a single shared sequence across all repos. Next free ID: **FR-069**.

---

## Open Requests

### FR-068: Analytics period metrics — MTD / month / quarter / YTD / YoY / by-year / all-time (both dashboards, unified date-range)
- **Repo(s)/area**: cross-repo — reservations (backend, base `staging`) + FM V3 (frontend, base `main`)
- **Status**: open (Mike parked to the backlog 2026-07-19 — was scoped & sized live, then parked before build)
- **Priority**: **medium** — real reporting gap (no current-month/quarter/year/all-time view today), but no live money/incident pressure. FR-066 and FR-067 (money, live) outrank it.
- **Phase-fit**: multi-PR; **already sized `ROUTE: PM`, 7 chunks** by project-evaluator — will re-enter via `/pm`, not `/letsbuild` solo. Money read path → `money-concurrency-reviewer` on P2/P3/S5 final heads.
- **Description**: FM reservations analytics can't express a reporting **period**. Add MTD / calendar month / quarter / YTD / year-over-year / by-year / all-time selection to the financial metrics **and** the transactions table, across **both** the Analytics (`/reservations/analytics`) and Financial Reports (`/reservations/financial-reports`) dashboards, on **one** unified date-range implementation.
- **Root cause (one sentence)**: there is no shared notion of a reporting period — date logic is duplicated three ways (analytics fleet-local DST-safe / legacy `/payments/report` naive-UTC / `PaymentReport.jsx` browser-TZ) behind a hard 366-day cap (`analytics.js:53` `MAX_RANGE_DAYS`), so calendar-aligned and multi-year periods are unrepresentable and identical dates yield different totals on different tabs.
- **Start here, do NOT re-derive — fully scoped already**: master plan at `~/.claude/plans/analytics-period-metrics-master-plan.md`; 7 dev briefs + status at `~/.claude/pm/analytics-period-metrics/` (chunks P1 resolver → P2 DB-side aggregate → P3 date-range unification → P4 cap-lift+YoY envelope → S5 transactions/pagination/auth → P6 PeriodSelector → P7 wiring). *(These live under `~/.claude` — Mac-local, not git-synced; if resuming on another machine, regenerate from this FR + the linked plan.)*
- **Decisions locked by Mike (2026-07-19, do NOT relitigate)**: (1) shared period component across BOTH surfaces + unify the three date-range impls onto fleet-local DST-safe; (2) lift `MAX_RANGE_DAYS` + **measure at prod scale before** building any rollup/materialized table; (3) **MANAGER-gate** `/payments/report` (currently serves decrypted payment PII behind any-role `authorizeFleet`) — audit non-manager consumers before flipping; (4) Rezo **imported** pre-launch history renders as a **separate series**, not merged into live revenue.
- **Sharp risks (found by project-evaluator, must survive to build)**: the aggregate path is `findMany`+JS-reduce, not a DB aggregate — uncapping it as-is is an **OOM**, so P2 (DB-side `groupBy`, push `source !== 'migration'` into the `where`) is a **hard prerequisite** to P4's cap-lift. P3's unification **moves a FULL DAY of revenue** into every payments report (legacy `lte: new Date(to)` parses UTC-midnight → last day currently EXCLUDED) — before/after capture on a real staging fleet is an acceptance requirement, and Mike must see it before prod. Prod promotion of anything touching `routes/reservations.js` is a **hand-port** (prod monolith vs staging split), not a cherry-pick. Prod pre-deploy money tests are vacuous without postgres — staging behavioral verify is the real gate.
- **Out of scope (recommended, NOT approved)**: CSV/XLSX export of a period's transactions; MoM/QoQ deltas; location breakdown row on the financial summary. Surface for approval at re-scope, don't auto-build.
- **Requested**: 2026-07-19

### FR-066: Public booking cart — server-quote the cart (kill the client price mirror)
- **Repo(s)/area**: reservations — backend (new public cart-quote endpoint) + frontend (public booking cart consumes it; delete the client mirror)
- **Status**: open (Mike parked to the backlog 2026-07-17; was the named "next project")
- **Priority**: **high** — this mirror is the GENERATOR behind the 2026-07-15 prod incident (cart showed $0, server charged $49.64). D2 (shipped in #1567) CONTAINS it — a stale/divergent cart now 409s `VOUCHER_DID_NOT_APPLY` instead of mischarging — so it currently presents as a wrong *display*, not lost money. The generator is still live.
- **Problem**: the booking cart displays a **client-side prediction** of a price only the server can compute. The client mirror kept missing server dimensions, one per review round — rule tier → quoting unit → model scope → type+size scope → **unit count**. Not typos; structural. (Author's round-4 zoom-out, doctrine rule 3.)
- **Root fix** (named by `outside-reviewer`): a server cart-quote endpoint — **POST selections → server returns per-line prices via `resolveSelections` + `_calculatePricing`**, i.e. the SAME code that computes the actual charge. One code path, zero drift. Needs NO `modelPriceKey`, NO `ruleSource` skip, NO new availability fields. **Revert `backend/src/routes/public.js:3506-3515`** — the field export that institutionalizes the mirror.
- **Start here, do NOT re-derive**: the full diagnosis is preserved as a comment on [reservations#1572](https://github.com/TheLineExp/fleetmanager-reservations/pull/1572).
- **Live state / hazards**: #1572 is **MERGED to staging** carrying 2 live P1s. **P1.1** — fleet hasn't priced a (bikeType, tier) → `public.js:3530-3544` drops the `byTypeSize` entry, `byBikeId` lacks those bikes → all 4 mirror rungs miss → the line **keeps the abandoned half-day price** (Mike's exact repro, unfixed); `frontend/src/__tests__/hooks/cartReprice.test.js:414` **asserts the broken behavior as correct**. **P1.2** — 2 riders same model, 1 unit free → client shows **$70**, server charges **$85** (`resolveSelections` dedups `assignedIds` across lines; the mirror only records existence) — `useBookingWizard.js:816`. 🚨 **Do NOT promote #1572's cart half to prod until the server-quote replaces it** — on staging P1.2 is an annoyance; on prod it's a customer charged more than the cart showed.
- **Also open on #1572 (P2)**: concierge parity gap (no `useCartQuote` there), location-blind price keys, rung order contradicts the server (`bikeId` vs `bikeIdForPrice`), tests never cover the dispatch path.
- **Phase-fit**: multi-PR; will divert `/letsbuild` → `/pm`. Money-path → `money-concurrency-reviewer` on final HEAD.
- **Requested**: 2026-07-17

### FR-067: Cap voucher issuer liability at face value (covered path is uncapped)
- **Repo(s)/area**: reservations (`voucherService` / `reservationService` pricing + discount) + vouchers (`offeringService` offer constraints)
- **Status**: open (Mike parked to the backlog 2026-07-17)
- **Priority**: **high — MONEY, live on prod today.** Pre-existing; found by `money-concurrency-reviewer` during w139 (2026-07-16), NOT introduced by it.
- **Problem**: the **covered** path returns `-subtotal` **UNCAPPED** (`backend/src/services/voucherService.js:217-219`, `calculateDiscount`, for `rental`/`full` passes) while the **upgrade** path caps at face value (`backend/src/services/reservationService.js:14344-14345`, `-Math.min(faceValue, subtotal)`). `discountApplied` (`reservationService.js:5559`) is what the **issuer** is billed → the issuer pays whatever length the customer picks. `offeringService.js:305` (vouchers) imposes no cardinality cap on `applicableTiers` either.
- **Concrete live case**: on an early-close override day the full_day pill is dropped (`DatesSection.jsx:322-324`), so a **`full_day`-ONLY** pass pre-selects **`multi_day`** → issuer billed `fullDay + (N-1)×perAdditionalDay` (N defaults to 2), uncapped, customer $0.
- **⚠️ COUNTERINTUITIVE — constraining offers to ONE tier does NOT close this.** `LEGACY_TO_TIER` is many-to-one (`multi_day → full_day`), so a **single-tier** `['full_day']` offer ALREADY covers `multi_day`. Offer-cardinality rules alone leave the hole open.
- **Root fix (needs Mike's product decision)**: cap issuer liability at face value on the covered path (making both paths symmetric), **OR** stop treating `multi_day` as covered by a `full_day` offer. Pick one; don't patch the call site.
- **Mike's framing (2026-07-16)**: "Voucher gets charged to issuer at the cost of the chosen length if there is more than one in the offer...which should not be the case. i dont think we specified a variable offer (bike type and location are variable)."
- **Phase-fit**: money-path; needs a product decision before design. `money-concurrency-reviewer` on final HEAD. Related: w139's pinned `PASS_DEFAULT_PRIORITY` prevents the *picker* from moving a pass's tier, but does NOT cap what the issuer pays.
- **Requested**: 2026-07-17

### FR-064: Bike Catalog — per-type descriptions + home-location matching + attached reviews/blogs (SEO/AI content layer on SSR)
- **Repo(s)/area**: cross-repo — reservations (public SSR catalog pages + content model + Schema.org Product/Review/BlogPosting + sitemap entries) + FM V3 (bike-type description/content admin + home-location mapping) · **content layer that sits ON the FR-063 SSR foundation**
- **Status**: open (parked 2026-07-15 — build AFTER FR-063 SSR migration lands; Mike explicitly gated it on "after we move to SSR")
- **Priority**: high (Mike: "critical piece of content for search engine and agent optimization and indexing" — this is the substantive discovery/indexable content the FR-063 plumbing exists to surface)
- **Phase-fit**: hard dependency on **FR-063** (needs the SSR framework, host→fleet resolution, and JSON-LD/robots/sitemap infra to exist first). Natural home for FR-063's parked **P7** (per-experience/per-bike URLs) and extends its P4 Product/Offer structured data with real catalog content. New multi-PR project; will divert `/letsbuild` → `/pm`.
- **Requested**: 2026-07-15
- **Source**: Mike, 2026-07-15 — "build a bike catalog after we move to SSR. I want a full bike catalog of all the types and descriptions of the bikes, then match the bike types with the locations they have listed as home. Critical for search-engine and agent optimization/indexing. Ideally we can attach reviews, blogs and other content to each bike/type."
- **Description**: A public, SSR-rendered, fully-indexable **bike catalog**: (1) an entry per **bike type** with a rich, structured description (specs, use-case, sizing, imagery); (2) each bike type **matched to the location(s) that list it as home** so the catalog is browsable by location and by type, and each fleet/location page can advertise its own inventory; (3) **attachable content per bike/type** — customer reviews, blog posts, guides, and other media — so each catalog entry accretes durable indexable content over time. All rendered server-side with Schema.org markup (Product / Offer / AggregateRating / Review / BlogPosting) and wired into robots/sitemap/llms so both Google and AI crawlers index every type and location.
- **Design questions (scoping pass required)**:
  - **Where the catalog/content model lives**: reservations DB (new `BikeCatalogEntry` / `BikeTypeContent` + `ContentAttachment` models, per-fleet or global-with-fleet-overrides?) vs FM V3 vs the Squarespace apex. Bike-type names are canonical in FM V3 (`BikeType.name`) and priced per-fleet in reservations (`PricingRule.bikeType`) — decide the source of truth and the seam (see the FR-046 drift lesson: catalog must not re-introduce a name registry that drifts).
  - **Global vs per-fleet catalog**: is `/bikes/:type` one canonical entry, or fleet-scoped (`<fleet-domain>/bikes/:type`)? Multi-tenant host model from FR-063 pushes toward per-fleet on each custom domain with a shared type description + per-fleet availability/pricing/home-location.
  - **Home-location matching source**: which field designates a bike type's "home" location(s) — derive from where inventory/`PricingRule` exists per fleet, or an explicit admin assignment? (Confirm against the current bike→location/fleet model.)
  - **Reviews source**: real post-rental customer reviews (net-new review-capture flow?) vs manually curated vs imported (Google reviews). AggregateRating needs a governed, non-fabricated source — do NOT synthesize reviews.
  - **Blog/content home**: apex `theline.bike` is Squarespace (out of scope in FR-063) — decide whether blogs live there and are linked, or are authored/hosted in-app for indexable co-location with the catalog.
  - **URL scheme + canonicalization** (coordinate with FR-063 P4/P6 `noindex` rules and canonical-to-primary-domain handling).
- **Notes**: **Blocked on FR-063** — do not start until the SSR framework + host resolution + JSON-LD/sitemap infra land (this is the content that makes FR-063 worthwhile). Reuse: FR-063's RR7 `meta`/loaders + JSON-LD helpers + host-driven sitemap/robots/llms, the public availability/pricing API (per-fleet type list + prices), FM V3 `BikeType` registry, the fleet/location model. Cross-links: **FR-063** (SSR/SEO foundation — its P7 per-bike URLs fold in here), **FR-045/FR-042** (per-type/experience content patterns), and the guided "Help Me Choose" finder (catalog entries should interlink with guided experiences for both SEO and UX). Watch: fabricated reviews/ratings (governance), content drift vs the canonical type registry (FR-046 lesson), and keeping transactional pages `noindex` while catalog pages index.

### FR-063: Public-site SEO + AI-search indexability (React Router 7 SSR migration)
- **Repo(s)/area**: reservations — `frontend/` (SSR migration) + `backend/` (host-driven robots/sitemap/llms + per-fleet SEO flag) + azure (Container Apps hosting change: static-nginx → Node SSR server)
- **Status**: open (plan drafted 2026-07-15, `~/.claude/plans/reservations-we-want-bright-whisper.md` — approach approved, parked before build)
- **Priority**: high (customer discovery + AI-search visibility; today the entire public booking site is invisible to Google's first pass and to all non-JS AI crawlers)
- **Phase-fit**: new multi-PR reservations project; will divert `/letsbuild` → `/pm` (large migration of a live transactional app). Ties into `docs/AGENT_BOOKING_PLAN.md:246-256` (robots/sitemap/Schema.org already listed as TODO) and the existing agent-booking API + `llms.txt`/`ai-plugin.json`.
- **Requested**: 2026-07-15
- **Source**: Mike, 2026-07-15 — "we want our reservations pages, guide-me and booking flow all indexed on Google … how do we make sure our full site gets indexed and added to AI searches as well." Building more extensive guidance into these pages, so discoverability of that content matters.
- **Root cause**: `frontend/` is a pure client-side-rendered Vite/React SPA served by nginx as an empty `<div id="root">` shell — non-JS crawlers (all AI crawlers: GPTBot/ClaudeBot/PerplexityBot/Google-Extended, + Google's first indexing pass) see no title/description/content on any URL. Zero SEO infra today (no robots.txt, sitemap, meta description, OG, canonical, or structured data — all verified MISSING).
- **Approved approach (decisions locked at planning)**: (1) **Full SSR migration** to React Router 7 *framework mode* (RR7 = Remix merge, built-in SSR) — the root-cause fix, not a bolt-on prerender. (2) **Index scope = discovery pages only** (fleet landing, guided "Help Me Choose" finder, future experience/bike guidance); transactional/tokenized pages (cart/checkout, confirmation, manage, rider, waiver, payment) explicitly `noindex`. (3) **Host-driven multi-tenant** SEO with a per-fleet `seoIndexingEnabled` toggle (default ON) — works for every fleet's custom domain; Azure fallback FQDNs → `Disallow: /` + canonical to primary domain. Apex `theline.bike` (Squarespace) is out of scope.
- **Phasing** (de-risked; full detail in the plan file): P0 SSR-safety audit + spike → P1 framework-mode scaffold at full parity (no SEO yet) → P2 hosting cutover (Node SSR behind existing nginx, preserve tuned CSP) → P3 server-side host→fleet resolution + isomorphic API → P4 content loaders + RR7 `meta` (title/description/canonical/OG/JSON-LD LocalBusiness/Product/Offer) → P5 host-driven robots.txt/sitemap.xml/llms.txt + per-fleet flag → P6 exclusions + bot-UA verification + Search Console/Bing onboarding → P7 (parked) per-experience URLs + FM V3 admin toggle UI.
- **Notes**: Reuse — existing public API + `resolve-host` (feed loaders), `backend/public/llms.txt`/`ai-plugin.json`/agent OpenAPI (surface on customer domain), nginx CSP block (extend, never replace — Codex-P1 history), `FleetProvider`/`FleetContext`, RR7 native `meta` (replaces react-helmet). Biggest risk = SSR-safety of Stripe Elements / Microsoft Clarity / kiosk mode / iframe embedding under hydration → hard parity gate in P1 before any SEO. Verification: `curl -A GPTBot` on staging returns real HTML+JSON-LD+content; transactional URLs `noindex`; Rich Results Test passes; sitemap submitted.

### FR-062: Return-to-service date required for out-of-service bikes (future-booking gate)
- **Repo(s)/area**: cross-repo — reservations (future availability gate) + FM V3 (status→OOS coupling, return-date UI, checkout override)
- **Status**: open
- **Priority**: P2 (correctness/UX; not a safety hole — present-state checkout gate + w72 still block service at pickup)
- **Phase-fit**: follow-up to the w72 present-state fix (`fmDb.isBikePresentAvailable`, LINE-DNRE63); reservations availability + FM V3 bike-status/OOS
- **Requested**: 2026-07-04
- **Source**: Mike, 2026-07-04 — after verifying w72, the deeper half: future-booking availability for non-ready bikes.
- **Core rule (Mike)**: (1) **No service/broken bike is future-bookable WITHOUT a return-to-service date** — no date ⇒ block all future windows (like today's indefinite-OOS); with a date ⇒ auto-rejoin for windows on/after it (windowed OOS, already works). (2) **Maintenance is NEVER a block** (present or future) — do not add maintenance to any gate; w72 fixed present-state. (3) **Failed-safety bikes that reach checkout are bumped there by fleet-manager push** — the present-state checkout gate + manager override is the acceptable backstop, NOT a requirement to perfectly pre-block every one.
- **Problem / evidence**: FM has two decoupled mechanisms — task-derived status (`service`=failed-safety/manual, `maintenance`=scheduled) sets NO availability fields; manual `bikeService.setOutOfService` sets `outOfServiceUntil` (dated auto-rejoin) / `outOfServiceSince`-no-date (indefinite) / `safetyHold` (broken). The future gate `availabilityService.isOutOfServiceAtStart` blocks only sold/retired + safetyHold + OOS-window and never reads `status='service'`. **Verified prod (The Line HQ, 35 non-ready bikes, 2026-07-04): ZERO bikes have a return date (`outOfServiceUntil`)** — the dated mechanism is unused; **3 of 7 `service` bikes have no OOS backing → currently future-bookable**, violating the core rule (in_use ×7 + maintenance ×7 correctly future-bookable; sold ×11 + Not-Ready ×2 correctly blocked).
- **Scope**:
  - (b) **reservations code** — `isOutOfServiceAtStart`: a `status='service'` (and however 'broken' is modeled) bike with no `outOfServiceUntil` blocks all future; with a date, block until the date. Blocks the 3 unbacked service bikes. Needs a parity-sweep (future-availability twins: `getAvailableBikes`, `bikeHorizonAvailability`, assertBookable).
  - (a) **FM V3 UI/process** — require (or strongly prompt) a return-to-service date, or explicit 'indefinite', whenever a bike is marked out-of-service or a failed-safety/manual service task opens, so staff actually set dates.
  - (c) **checkout** — confirm the fleet-manager override/push path handles a failed-safety bike at checkout (present-state gate already blocks; verify the manager can push through with reason + audit).
- **Design Qs**: exact status/flags for 'broken' vs 'service' (is `safetyHold` the broken flag?); which statuses gate the future path (service only, or a set); auto-rejoin on service-task-close vs wait-for-date; **confirm the in_use invariant** — in_use bikes have NO OOS backing and rely solely on the reservation-conflict overlap on their active rental; close any non-reservation / demo / walk-in checkout leak.
- **Acceptance**: no service/broken bike is future-bookable without a return-to-service date; maintenance never blocks; failed-safety at checkout handled by manager push.
- **Notes**: see memory `maintenance-not-a-rental-block`. The reservations code piece (b) is small (~a couple lines in `isOutOfServiceAtStart`) but is a future-booking behavior change and needs the FM V3 return-date UI (a) to be usable + a parity-sweep — can be expedited independently if Mike wants the 3 bikes blocked sooner.

### FR-061: Partner Booking Portal + Automated Commission Payouts (Stripe Connect)
- **Repo(s)/area**: cross-repo — reservations (Affiliate upgrade + partner Connect onboarding + payout job + standalone partner portal) + FM V3 (admin create-partner) · builds on the in-flight `wpay-settlement` Connect-charging work
- **Status**: open (planned — plan approved 2026-06-29, `~/.claude/plans/we-need-a-way-noble-brook.md`)
- **Priority**: high
- **Phase-fit**: continuation of reservations `wpay-settlement` (the Connect platform-fee substrate) + extension of the shipped FR-006 / Phase 21A affiliate system. New multi-PR project; Phase 3 sequences after `wpay-settlement` lands.
- **Requested**: 2026-06-29
- **Source**: Mike, 2026-06-29 — hotel/hospitality partners (e.g. "FluidRide") book bikes for their clients through a partner portal/flow and earn a commission, paid out automatically via Stripe Connect on a schedule, with full reporting to fleet + partner.
- **Description**: A fleet manager partners with an external org and pays them a commission. Onboard a partner (info + a Stripe Connect account, mirroring the FM V3 fleet OAuth onboarding one layer down), assign a commission % + payout cadence (daily/weekly/monthly), attribute bookings to the partner (referral code — already shipped), accrue commission, **fund it as an extra `application_fee` component on top of the existing 3% software fee so it lands in the platform balance, then transfer it out to the partner's connected account on schedule**, and report it. Guest pays at checkout (full public flow reused incl. voucher + add-ons). Partner portal works like the vouchers portal but is its OWN surface in the reservations app (vouchers is being spun out).
- **Notes**: ~70% already exists — reservations `Affiliate`/`AffiliateAttribution`/`AffiliatePayout` (FR-006, commission-on-subtotal, attribution via `?ref=`, manual payout today); FM V3 fleet Connect OAuth onboarding (`stripeConnectService`); `wpay-settlement`'s `platformFeeService` (3% application_fee), `connectChargeMode`, `settlementService`, `fmDb.getFleetConnect`, `refund_application_fee`; vouchers payout engine as a *pattern* (no coupling). **The one missing primitive: a `stripe.transfers.create` transfer-OUT to a third-party connected account** — own it in `settlementService`. Connect-enabled fleets only (Suncadia is the pilot); The Line on legacy Stripe falls back to manual payout. Phasing: (1) partner identity + Connect onboarding; (2) standalone partner portal (magic-link auth, onboarding wizard, dashboard, book-for-client, reports); (3) automated scheduled payouts (on `wpay-settlement`); (4) full reporting. Full plan: `~/.claude/plans/we-need-a-way-noble-brook.md`.

### FR-060: De-VoloPass code scrub (legal) — remove "VoloPass"/"Volo" from ALL code
- **Repo(s)/area**: cross-repo — vouchers + reservations + FM V3 + azure
- **Status**: open
- **Priority**: P1 / high (legal jeopardy over the "VoloPass"/"Volo" brand)
- **Phase-fit**: new cross-repo "de-brand" project — needs its own scoping plan (migration + coordinated contract changes + Azure renames + staged deploy)
- **Requested**: 2026-06-29
- **Source**: Mike, 2026-06-29 — wants "VoloPass" scrubbed from the codebase entirely, not just user-facing strings.
- **Description**: The brand was already retired *user-facing* via configurable `BRAND_NAME` ("The Line Vouchers"). This FR is the **internal-identifier scrub**: rename `/admin/volopass/*` and `/volopass-offerings` **route paths**, `volopass*` **API field names** (cross-repo contracts between vouchers ↔ reservations ↔ FM V3), `Volopass*` **Prisma models/columns** (needs a migration), `Volopass*`/`volopass*` **filenames + identifiers** (e.g. `VolopassOfferings.jsx`, `SystemVolopassLayout`, `volopassConnectClient`, `useVolopassOffering*`), and the **Azure resource names** (`vouchers-api-*` etc.).
- **Notes**: **Reverses** the explicit "do not rename volopass internal identifiers" guidance in all 3 CLAUDE.md files (vouchers / FM V3 / reservations) — update those sections + the `volopass-rebrand-configurable` memory when this runs. Until this lands, all NEW code must use neutral "voucher"/"offering" naming (in force as of 2026-06-29; first feature built under that rule = offering visibility + voucher-aware cleanup, plan `crystalline-orbiting-summit`). Coordinate route/field/model renames as versioned contract changes so the 3 services don't break mid-deploy. Pairs with the standalone-extraction directive (voucher logic stays in the vouchers service).

### FR-059: Reusable Voucher Cards — durable, reassignable physical card pool over the single-use engine
- **Repo(s)/area**: cross-repo — vouchers (new `ReusableCard` + `CardAssignment` models, `cardService`, service/partner/admin endpoints, redeem/release hooks) + vouchers **portal** (distributor operator UI) + reservations (serial→code resolution seam in `voucherService.js`) + optional FM V3 system-level inventory tab
- **Status**: open
- **Priority**: P2 (net-new capability, no live incident)
- **Phase-fit**: new cross-repo VoloPass "card-pool" phase — additive over the existing `voucherService`; coordinate with FR-056
- **Requested**: 2026-06-26
- **Source**: Mike, 2026-06-26 — wants durable plastic cards (printed once) that a front-desk **distributor reassigns to a new guest each visit**, instead of printing disposable one-time-code cards. Full design + codebase exploration in plan `~/.claude/plans/ok-i-have-a-stateless-badger.md`.
- **Decisions captured**: token = reusable card **serial** (no phone/PII); grants = **reassignable, one ride each**; activation = **operator/distributor enrolls** (scan serial + pick program; no public activation step); scope = design-first, multi-PR.
- **Core principle**: do **NOT** make a voucher multi-use — the budget/invoice/cap/audit layer assumes 1 redemption = 1 voucher (`Voucher.code @unique`, terminal `redeemed`, optimistic lock in `voucherService.redeemVoucher`). Instead a durable **card token** is a thin reloadable **alias** that mints ONE ordinary single-use voucher per assignment. Card reusable; voucher not; all accounting stays verbatim; the change is purely additive.
- **Card lifecycle**: `blank → assigned` (mint 1 voucher under a program, counts vs budget) `→ used` (booking redeems via the existing path; NOT auto-unbound, so operator stays in control and a cancel can revert) `→ reassign` (void/release old voucher, mint fresh) ; retire any time. Release/cancel reverts `used→assigned` only if the card still points at that voucher (else the released voucher returns to the program pool as normal — documented edge).
- **Data model** (vouchers `schema.prisma`): `ReusableCard { id, serial @unique, status blank|assigned|used|retired, fleetId+issuingOrgId(+distributorId), currentVoucherId @unique FK→Voucher, currentProgramId, assignedAt/By, note, timesUsed, timestamps }` + append-only `CardAssignment` (mirrors `VoucherEvent`) `{ cardId, voucherId, programId, action assigned|redeemed|released|reassigned|retired, actor, metadata }`. No change to `Voucher`/`VoucherProgram`/budget fields.
- **Reservations seam (minimal)**: resolve serial→current voucher code via new `GET /api/service/card?serial=&fleetId=`, then feed into the **unchanged** validate/redeem/release/outbox path keyed on the resolved code. No change to `createReservation`/pricing/outbox columns/`voucherReconciliationJob`.
- **Operator UI = vouchers PORTAL** (`portal/src/pages/`), NOT FM V3 — card assignment is a tenant-scoped distributor op per the canonical-surface split rule (ADR `docs/architecture/portal-as-canonical-tenant-surface.md`). FM V3 gets at most a read-only system-level inventory tab.
- **Reuse**: `codeGenerator.generateBulkCodes` (mint 1) · existing `count>remaining` budget guard (`routes/admin.js` ~1145) · `redeemVoucher`/`releaseVoucher` unchanged · status-guarded `$transaction` optimistic lock (same as redeem) · `VoucherEvent`→`CardAssignment` audit pattern · existing reservations outbox + reconciliation job · `vouchersAPI.cardPdf`/CSV export for a printable serial sheet.
- **Risk/adversarial (voucher+state+concurrency — pre-push parity sweep applies)**: double-assign guarded by status-guarded `$transaction` (`WHERE status IN ('blank','used')`); the auto-mark-`used` card update MUST be the 3rd op INSIDE the existing redeem `$transaction` (else a redeemed card sticks at `assigned`); cancel/rebind symmetry edge above; budget accounting unchanged (incl. the known bulk-purge cap-undercount); tenant scoping via `expectedFleetId`; pre-redemption release/reassign must void the pending voucher so it doesn't permanently consume a budget slot.
- **Phasing**: (1) vouchers backend models+migration+`cardService`+hooks+endpoints+tests; (2) vouchers portal distributor Reusable Cards inventory + assign/reassign/release/retire; (3) reservations serial→code seam + tests; (4) optional FM V3 inventory tab + serial-batch printable sheet.
- **Cross-links**: **FR-056** (VoloPass reserved→used two-phase lifecycle — if it lands first, card-minted vouchers ride the same lifecycle for free) and the **customer types/segments FR** (the deferred phone-as-identity path — keep the token model compatible so phone can be added later as a second token type).

"### FR-058: Rental-length controls — per-fleet max rental days + Month block toggle
**Repo(s)/area:** reservations (backend + public flow) + FM V3 (admin) · pricing/booking-policy

**Why:** Today `month` is only a price *cap* applied in `pricingResolver.computeMultiDayBikePrice` (`Math.min(total, month)`), NOT a duration a customer picks, and there is **no maximum rental length** — so a customer can already book 30/60/90 days via the multi-day picker (the month rate just caps the price). Owner: "we don't want to rent bikes for months at a time," and wants Month controllable like the other pricing types. (Surfaced verifying PR-8c-3b on staging, 2026-06-24.)

**Scope (per-fleet, owner-confirmed):**
- **Part A — Max rental length.** New `BookingFieldConfig.maxRentalDays Int?` (null = unlimited; migration). Admin input in FM V3 FieldConfigSettings. Public multi-day picker clamps week-chips + day-stepper to `min(maxRentalDays, advanceBookingDays)` + "max N days" hint (DatesSection.jsx). Backend commit gate in `reservationService.createReservation` rejects non-staff multi_day bookings whose inclusive day-count > maxRentalDays (mirror `assertBlockEnabled` placement + `effectiveSource !== 'staff'` bypass). Public GET `/fleet/:id/booking-field-config` already returns the row — add the default.
- **Part B — Month toggle.** FM V3 PricingSettings: add `month` to the matrix enable/disable toggles (default-on; EXEMPT from the enable↔price guard since a cap with no rate = no cap). Gate the month cap on `isBlockEnabled(cfg,'month')` at all 5 `computeMultiDayBikePrice` callers (catalog ×2, availability/v2 ×2, _calculatePricing ×1).

**Status (2026-06-24):** **Part A (max rental length) SHIPPED to staging** — reservations [#1245](https://github.com/TheLineExp/fleetmanager-reservations/pull/1245) (schema/migration + commit gate over ALL duration types incl. long_term + admin PUT + public GET + both public pickers clamped) + FM V3 [#1124](https://github.com/TheLineExp/Fleetmanager_V3/pull/1124) (maxRentalDays admin input), both merged. Codex round fixed (long_term gate, stale-numDays clamp, concierge picker). Pending → prod. **Part B (Month enable/disable toggle): PARKED** — max rental length already delivers the 'no months' goal, so the month *cap* toggle is now largely cosmetic; build only if the owner still wants matrix parity. Related: FF10 (gate reschedule/self-modify for max-length + block-enable, both create-only today).


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
- **Phase-fit**: new phase — deploy/infra hardening. Builds on the existing custom-domain-binding guard in `deploy.yml`.
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

### FR-065: Reservations — pre-existing money + window-bucketing latent bugs (3 root causes, not call-site patches)
- **Repo(s)/area**: reservations (primary) + FM V3 (the bucketing half of the setup-prep worklist) · cross-repo
- **Status**: open (parked 2026-07-16 — Mike explicitly chose to park ALL of these to close down the `mid-rental-edit-in-progress` workstream)
- **Priority**: medium — **contains 3 MONEY items**, but every one is **pre-existing and latent** (none introduced by the mid-rental-edit work, none blocking its ship, zero reported customer incidents to date). Raise to high if any surfaces live.
- **Phase-fit**: new scoping pass. Three of these are **shared-helper extractions** — that's what makes this a feature-sized project rather than a `/todo` batch: patching the call sites is what keeps regenerating these findings.
- **Requested**: 2026-07-16
- **Source**: surfaced by the `track-f-complete` milestone reviews (money-concurrency + parity-sweep) during the mid-rental-edit program, 2026-07-15/16. Evidence: `~/.claude/pm/mid-rental-edit-in-progress/reviews/milestone-track-f-complete-{money,parity}.md` and `-{money,parity}-rerun.md`.
- **Description**: Successive adversarial sweeps kept re-surfacing the same three defect *families*. Each family's root cause is a **missing or under-specified shared guard**, so every fix at a call site leaves siblings live and the next sweep finds them again. This FR is to fix the three roots once, then adopt them everywhere.

  **① Billed-vs-physical window bucketing has no shared helper.** F3 (#1570) wrote an `effectivePickupInstant` helper **local to `dailyRosterService.js`**; every other consumer still re-derives (or forgets) the `COALESCE(physicalStartTime, startTime)` rule. Known stragglers: `reservation/scheduling.js:460-556` (`getLocationSummary`/`getLocationSummaries` → FM V3 Locations dashboard `pickupsToday`/`returnsToday`), `reservation/listing.js:~604-673` (`getDashboardCounts` badge chips). Also the **setup-prep worklist**, which needs a **cross-repo** fix — a reservations-side change alone is a **no-op** because both FM V3 callers hard-code `days=30` (`integrations.js:478`, `bikeService.js:413/433`, `reservationUtils.js:80`); the real narrowing is FM V3 re-bucketing on the billed start. **Root fix: extract the helper to a shared module + adopt at every consumer, both repos.** (An earlier framing of this worklist — "days=1 misses tonight's pickup" — was investigated and proven a **no-op with no reachable caller**; re-verify the premise before building.)

  **② CAS key is under-specified [MONEY].** `_commitRepricedTotalCas` keys on `totalAmount` **only**, and no `paymentStatus` writer touches `totalAmount` — so a capture landing mid-reprice passes the CAS unchanged. `selfService.js:1211→:1668→:1772/:1779`: **$200 captured / $150 written / no refund.** Fix is one line on each CAS site (`paymentStatus: reservation.paymentStatus` in the `where`), but the real lesson is that the *guard* is under-specified — same class as F1's non-exhaustive writer list, one level up.

  **③ Overlap checks bypass the shared helper.** `reservation/edit.js:2607-2631` — `rescheduleReservation`'s in-tx race-window bike-conflict recheck hand-rolls its own `startTime`-only OR instead of using `availabilityService.holdOverlapOR` → narrow but real **double-booking hole** for a concurrent early-pickup hold. **Root fix: every overlap check goes through the shared helper.**

- **Also in scope (smaller, same sweep)**:
  - **[MONEY]** `/refund` full-refund over-collect vector — a non-E1 full refund via `/refund` does **not** reduce `totalAmount`, so a payment link can over-collect. (This is the vector the `SETTLED_PAYMENT_STATUSES += 'refunded'` band-aid was reverted out of E1 for — it belongs here, fixed properly with its own money-reviewer pass.)
  - `reservation/settlement.js:527-540` — the increment fallback composes additive fields but applies `_priceOverrideClearFields()` **absolutely**, so an override landing inside the recompute window leaves its dollars baked in with no marker → silent clawback next reprice. The already-fixed shape exists at `edit.js:2199-2205` (add-bike path) — copy it.
  - Legacy `POST /:id/reschedule` **free-extend twin** — never reprices (extends the window for free) and **nulls `physicalStartTime`** on active. Not reachable from current FM V3 (callers preserve duration), so no live loss — but note **two independent reviewers found two different defects in this same path** (this + ③), which argues for hardening it as one unit.
  - C1 `priceAction:'keep'` accepted on an **active extend** → free longer window. C2 blocks it in the UI, but that is **not durable** (API-direct clients bypass it).
  - **[MONEY]** `adminDiscountAmount` omitted from the removal reprice (both money reviewers independently confirmed no over-refund today).
  - `getTabCounts` / `_applyTabFilter` **billed-date semantics** — a **product call, not a defect**; needs Mike to define intended behavior before anyone builds.
  - `nonReadyDigestJob.js:92` — low, self-heals.
  - `BikePickerModal.jsx` renders hand-rolled settlement copy as a bare `<p>` — should point at the shared `SettlementNotice`/`AlertBox` (cosmetic; same class as the C2 Fix-3 that already landed).
- **Notes**: Do **not** file these as separate FRs — they were deliberately consolidated into one entry because splitting them is what made the parent workstream feel endless. The three roots (①②③) should be scoped together; the smaller items are cheap riders once the roots land. **Prod caveat**: prod runs the monolithic `reservationService.js`, so any fix here needs the same hand-port treatment as the mid-rental-edit batch (see `staging-prod-module-refactor-divergence`).

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
