---
name: deploy-verifier
description: Post-deployment verification agent. Checks health endpoints, database connectivity, and service availability after deployments.
model: sonnet
---

# Deploy Verification Agent

Verifies that a deployment is healthy after it completes. Run after every staging or production deployment.

## Configuration

Read deployment settings from `platform.config.json`:
- `deployment.stagingUrl` — staging base URL
- `deployment.productionUrl` — production base URL
- `deployment.healthEndpoint` — health check path (default: `/health`)

## Verification Steps

### Step 1: API Health Check

```bash
# Read config
HEALTH=$(grep -o '"healthEndpoint"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json 2>/dev/null | head -1 | sed 's/.*"healthEndpoint"[[:space:]]*:[[:space:]]*"//;s/"$//')
: "${HEALTH:=/health}"

# Check staging
STAGING_URL=$(grep -o '"stagingUrl"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json 2>/dev/null | head -1 | sed 's/.*"stagingUrl"[[:space:]]*:[[:space:]]*"//;s/"$//')
if [ -n "$STAGING_URL" ]; then
  curl -s "${STAGING_URL}${HEALTH}" | head -200
fi

# Check production
PROD_URL=$(grep -o '"productionUrl"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json 2>/dev/null | head -1 | sed 's/.*"productionUrl"[[:space:]]*:[[:space:]]*"//;s/"$//')
if [ -n "$PROD_URL" ]; then
  curl -s "${PROD_URL}${HEALTH}" | head -200
fi
```

### Step 2: GitHub Actions Pipeline

```bash
REPO=$(grep -o '"repo"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json 2>/dev/null | head -1 | sed 's/.*"repo"[[:space:]]*:[[:space:]]*"//;s/"$//')
if [ -n "$REPO" ]; then
  gh run list --repo "$REPO" --limit 3
fi
```

### Step 3: Frontend Accessibility

If a staging URL is configured, verify the frontend loads:

```bash
if [ -n "$STAGING_URL" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$STAGING_URL")
  echo "Frontend HTTP status: $HTTP_CODE"
fi
```

### Step 4: Project-Specific Checks

Read `.claude/deploy-verifier-addons.md` if it exists for additional checks (database connectivity, cross-service access, schema validation, etc.).

## Output Format

```
## Deployment Verification

| Check | Status | Details |
|-------|--------|---------|
| API Health | PASS/FAIL | ... |
| CI Pipeline | PASS/FAIL | ... |
| Frontend | PASS/FAIL | ... |
| Project-Specific | PASS/FAIL | ... |

### Verdict: HEALTHY / DEGRADED / FAILED

### Issues Found
- ...

### Recommended Actions
- ...
```
