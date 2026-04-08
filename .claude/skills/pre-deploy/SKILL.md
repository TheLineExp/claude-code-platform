---
name: pre-deploy
description: Comprehensive pre-deployment checklist. Runs code quality, security, testing, and deployment readiness checks. Use before deploying to staging or production.
user_invocable: true
---

# Pre-Deploy Checklist

Comprehensive pre-deployment validation. Run this before `/shipit`.

## When to Use

- Before deploying any changes to staging or production
- When the user asks for a "pre-deploy check" or "deployment readiness"

## Checklist (10 Sections)

### 1. Code Quality
- [ ] No debug statements (console.log, print, debugger)
- [ ] No commented-out code blocks
- [ ] No TODO/FIXME/HACK comments in changed files
- [ ] Functions follow single responsibility principle
- [ ] Error handling is comprehensive

### 2. Security
Run `/security-review` or check:
- [ ] No hardcoded secrets
- [ ] Authentication on all protected routes
- [ ] Authorization checks enforced
- [ ] Input validation on all endpoints
- [ ] No known vulnerability in dependencies (`npm audit` / `pip audit`)

### 3. Testing
- [ ] All tests pass: run test command from `platform.config.json`
- [ ] New features have corresponding tests
- [ ] Test coverage meets threshold
- [ ] Edge cases covered (empty inputs, boundaries, errors)

### 4. Database
- [ ] Migrations are idempotent (IF NOT EXISTS / IF EXISTS)
- [ ] No breaking schema changes without migration plan
- [ ] Indexes added for new query patterns
- [ ] Data integrity preserved (foreign keys, constraints)

### 5. API Compatibility
- [ ] No breaking changes to existing endpoints
- [ ] Deprecated endpoints still function
- [ ] New endpoints documented
- [ ] Response format consistent with existing endpoints

### 6. Configuration
- [ ] Environment variables documented
- [ ] No environment-specific values hardcoded
- [ ] Feature flags configured correctly
- [ ] Secrets referenced properly (not plaintext)

### 7. Performance
- [ ] No N+1 queries introduced
- [ ] Large datasets paginated
- [ ] New endpoints have rate limiting
- [ ] No blocking operations in request handlers

### 8. Monitoring & Logging
- [ ] Error logging for failure paths
- [ ] Health check endpoint works
- [ ] Key operations logged for debugging

### 9. Documentation
- [ ] CHANGELOG updated (or changelog entry created)
- [ ] API documentation updated for new/changed endpoints
- [ ] README updated if setup steps changed

### 10. Project-Specific Checks

**Read `.claude/pre-deploy-addons.md` if it exists.** Apply infrastructure, cloud provider, and project-specific deployment checks.

## Verdict

After completing all sections:

```
## Pre-Deploy Assessment

Status: READY / READY_WITH_WARNINGS / NOT_READY

### Summary
- Sections passed: X/10
- Critical issues: N
- Warnings: N

### Blocking Issues (must fix)
- ...

### Warnings (should fix)
- ...

### Recommendation
[Deploy / Fix first / Needs discussion]
```
