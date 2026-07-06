# shipit — deploy reference (CI/CD · order · post-deploy · errors)

Loaded on demand by the `shipit` core skill. Pure lookup material consulted at specific
moments — not workflow steps. Read the relevant section when you need it.

## CI/CD Pipeline (both repos)

The deploy pipeline runs these jobs in order:
1. **Setup** — determine environment from branch (staging vs production)
2. **Pre-deploy Tests** — unit tests + frontend build check
3. **Build Images** — Docker build + push to `fleetmanageracr.azurecr.io`
4. **Deploy Backend** — update Azure Container App + health check
5. **Deploy Frontend** — update Azure Container App + health check
6. **Database Migrations** — 3-step idempotent pipeline:
   - `repair-migrations.js` — sync checksums + detect/fix drift
   - `npx prisma migrate deploy` — apply pending migrations (all SQL is idempotent)
   - `verify-schema.js` — verify 123 canary checks pass
7. **Summary** — print deployment URLs

All migrations use IF NOT EXISTS / IF EXISTS guards. No more baselining, retry loops, or failure cascading. Skip migrations with `skip_migrations: true` in workflow dispatch.

## Deployment Order (when shipping multiple repos)

If changes span multiple repos, deploy in this order:
1. **Vouchers first** (if involved) — backend service endpoints other repos depend on
2. **Reservations second** — depends on Voucher API, provides API for FM V3 frontend
3. **FM V3 last** — frontend depends on both Reservations and Voucher APIs

## Post-Deploy Verification

After the user merges and production deploys:

```bash
# FM V3
curl -s https://fleetmanager-api-prod.blackmeadow-d39ebc45.westus2.azurecontainerapps.io/api/health
# Expected: {"success":true,"message":"The Line Fleet Manager API is running",...}

# Reservations
curl -s https://reservations-api-prod.blackmeadow-d39ebc45.westus2.azurecontainerapps.io/health
# Expected: {"status":"ok","service":"fleetmanager-reservations","environment":"production",...}
```

## Error Handling

- **Uncommitted changes in staging**: Stash or commit them first
- **Merge conflicts**: Resolve manually before continuing
- **PR already exists**: Update existing PR or link to it
- **Push rejected**: Pull latest changes and retry
- **Deploy fails**: Check `gh run view <id>` for details, check container logs with `az containerapp logs show`
