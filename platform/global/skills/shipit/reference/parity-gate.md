# shipit — Step 1b sweep checklist (Parts 1–3)

Loaded on demand by the `shipit` core skill's Step 1b. This is the SPEC the `parity-sweep` and
`money-concurrency-reviewer` agents must cover — and the manual fallback if the agents are
unavailable. Run it whenever Step 1b's mechanical trigger fired (payment/refund/voucher,
state transition, shared helper/serializer, auth/role gate, or concurrency). A sweep with no
CHECKED-CLEAN entries, or any BLOCK verdict, blocks the ship — fix and re-run.

**Part 1 — Parity sweep (cross-site consistency).** For each symbol/route/flag/derived-value/guard/contract in the diff:
```bash
# every consumer of a symbol/helper you changed — are they ALL consistent with the new behavior?
rg -n "<symbolOrHelperName>" backend/src frontend/src
# twin-route parity: does the org↔distributor / staff↔public sibling exist AND carry the same gate?
rg -n "<routePath>|requireRole|isManagerForFleet|requirePartnerRole" backend/src/routes
# flag threaded through the WHOLE chain (not just the entry gate)?
rg -n "allowClosedDays|mode:\s*'STAFF'|readOnly" backend/src
# migration registered in BOTH canaries?
rg -n "<migration_name>" backend/scripts/verify-schema.js backend/scripts/repair-migrations.js
# any test still asserting the OLD shape/value?
rg -n "<oldValueOrHeadingOrField>" -g '*.test.*'
```
RED FLAGS → BLOCK: a derived value (displayStatus, fleet-tz time, `waiverSigned`) rendered raw
on a parallel surface; a flag set at one gate but re-rejected by a downstream sibling; a new
route whose twin lacks the role gate; a client sending a field/route the server doesn't
consume/expose; a migration missing from a canary; a test asserting the pre-change shape.

**Part 2 — Adversarial state / concurrency.** For payment/state-machine/shared-mutable code, write the answer to each:
- For EACH exit branch of the changed function, what value does it read or RESTORE — and is it
  stale if a second request ran concurrently? (refund lock-release-to-stale-status, over-issue TOCTOU.)
- Is every read of mutable balance/status/idempotency INSIDE the lock? Nothing read before the
  lock that's used after it.
- Is the idempotency key unique per logical operation AND written atomically under the lock?
- After any reorder/refactor: diff the GUARD SET — did `amountCents<=0`, a status-in-set check,
  or similar get dropped or bypassed? Re-derive the whole state machine; do NOT patch only the
  reported symptom.
BLOCK on any "it's stale / not under the lock / a guard moved."

**Part 3 — Edge / sub-case / trust-boundary.** Enumerate explicitly (don't assume the common case):
- Sub-cases under every new default/branch: no-payment, $0/negative, authorized-vs-captured,
  already-refunded/returned, empty/single-element, reversed/zero-length window.
- Trust-boundary inputs: string query/form flags parsed explicitly (NOT `Boolean(req.query.x)` —
  `'false'` is truthy); fetched URLs canonicalized + private-range-blocked + byte-bounded (SSRF);
  a new mutation/delivery route copies the adjacent route's auth gate.
BLOCK on any unhandled sub-case or unguarded boundary input.

**Output:** list what you swept, found, and fixed — e.g. "Parity: checked 3 consumers of
`computeRefundable`, fixed month-serializer rendering raw status. Concurrency: moved
`alreadyRefundedCents` read inside the lock. Edge: added no-payment + $0 guards." If you
genuinely skipped this step, state which change type made it safe to skip.
