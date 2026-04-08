# Code Review Addons — FleetManager Reservations

## Security (Critical — PII System)
- [ ] All customer PII encrypted with `encryptionService` (AES-256-GCM)
- [ ] Searchable fields have HMAC hashes (`encryptionService.hash()`)
- [ ] License data encrypted with separate LICENSE_ENCRYPTION_KEY
- [ ] Driver's licenses deleted after rental period
- [ ] All routes require JWT auth (`authenticate` middleware)
- [ ] Fleet-scoped ops verify access (`authorizeFleet`)
- [ ] PII access logged with `auditService.log()`
- [ ] Rate limiting on sensitive endpoints

## Architecture
- [ ] Business logic in `backend/src/services/` (not routes)
- [ ] Routes are thin — validate input, delegate to service, return response
- [ ] Use `asyncHandler` wrapper on all Express routes
- [ ] Use `encryptFields()` and `decryptFields()` helpers
- [ ] Validation via `backend/src/utils/validation.js`

## Domain Rules
- [ ] Bikes assigned by specific `bikeId` (NEVER generic type+size slots)
- [ ] All dates in UTC ISO format (`new Date().toISOString()`)
- [ ] Vouchers are NOT coupons — distinct legal/accounting product
- [ ] SPs are mechanics only — no reservation access
- [ ] All fleet-scoped routes require `fleetId` UUID query param

## Database
- [ ] Migrations use IF NOT EXISTS / IF EXISTS guards
- [ ] Update `repair-migrations.js` + `verify-schema.js` canary checks for new migrations
- [ ] Prisma `include` for related data (no N+1 queries)
- [ ] All queries filter by `fleetId` (multi-tenant isolation)

## Frontend
- [ ] No toast notifications (use optimistic UI, button states, inline messages)
- [ ] No hardcoded colors/spacing — use `var(--color-*)`, `var(--spacing-*)`
- [ ] CSS Modules only (no global .css files)
- [ ] Action feedback: `savingAction` state + `AlertBox` on every async handler
