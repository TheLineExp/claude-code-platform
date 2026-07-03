---
name: traceability-review
description: End-to-end call chain verification across UI → API Client → Backend Route → Service → Database. Traces every button, link, and form action through all layers to verify function signatures, argument passing, and return values match. Use after implementing features, before deploying, or when hearing "trace", "verify calls", "check wiring", or "/traceability-review".
user_invocable: true
---

# Traceability Review Skill

**End-to-end call chain verification.** Ensures every UI action correctly calls through API client → backend route → service → database, and that data flows back correctly.

## When to Use

- After implementing or modifying features that touch multiple layers
- Before deployment (integrated into `/shipit` workflow)
- When debugging "undefined" errors, 404s, or wrong data in the UI
- When refactoring API clients, routes, or service signatures

Invoke with `/traceability-review` or when hearing "trace the calls", "verify wiring", "check call chain".

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│  FM V3 Repo (Frontend)                                  │
│  ┌───────────┐   ┌──────────┐   ┌───────────────────┐  │
│  │ UI Action  │──▶│  Hook    │──▶│  API Client Fn    │  │
│  │ (onClick)  │   │ (useQuery│   │ (reservationsAPI) │  │
│  └───────────┘   │ useMutate)│   └────────┬──────────┘  │
│                  └──────────┘            │ HTTP          │
├──────────────────────────────────────────┼──────────────┤
│  Reservations Repo (Backend)             │              │
│  ┌──────────┐   ┌──────────┐   ┌────────▼──────────┐  │
│  │ Prisma   │◀──│ Service  │◀──│  Express Route    │  │
│  │ (DB)     │   │ (Logic)  │   │  (+ Middleware)   │  │
│  └──────────┘   └──────────┘   └───────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### File Locations

| Layer | Repo | Path |
|-------|------|------|
| UI Components | FM V3 | `frontend/src/pages/reservations/` |
| React Query Hooks | FM V3 | `frontend/src/hooks/queries/useReservations.js` |
| API Client | FM V3 | `frontend/src/api/reservations.js` |
| HTTP Client | FM V3 | `frontend/src/api/reservationsClient.js` |
| Express Routes | Reservations | `backend/src/routes/*.js` |
| Middleware | Reservations | `backend/src/middleware/` |
| Services | Reservations | `backend/src/services/*.js` |
| Prisma Schema | Reservations | `backend/prisma/schema.prisma` |

---

## Execution Process

### Step 1: Identify Changed Files

Determine scope by checking both repos:

```bash
echo "=== FM V3 REPO (Frontend) ==="
cd "C:\Users\MichaelKunz\Documents\fleetmanager\Fleetmanager_V3"
git diff --name-only HEAD~1 | grep -E '\.(jsx|js)$' | grep -E 'pages/|api/|hooks/'

echo ""
echo "=== RESERVATIONS REPO (Backend) ==="
cd "C:\Users\MichaelKunz\Documents\fleetmanager-reservations"
git diff --name-only HEAD~1 | grep -E '\.(js|prisma)$' | grep -E 'routes/|services/|middleware/|schema'
```

### Step 2: Map UI Actions to API Calls

For each changed UI component, find all user actions that trigger API calls:

```bash
echo "=== UI ACTIONS IN CHANGED FILES ==="
# Find onClick, onSubmit, useMutation, useQuery references
grep -rn "onClick\|onSubmit\|useMutation\|useQuery\|handleClick\|handleSubmit" \
  "C:\Users\MichaelKunz\Documents\fleetmanager\Fleetmanager_V3\frontend\src\pages\reservations" \
  --include="*.jsx" | head -30
```

### Step 3: Trace API Client Functions

For each API call found, verify it maps to a real API client function:

```bash
echo "=== API CLIENT FUNCTIONS ==="
# List all exported API functions
grep -n "^\s*\w\+:" \
  "C:\Users\MichaelKunz\Documents\fleetmanager\Fleetmanager_V3\frontend\src\api\reservations.js"
```

### Step 4: Match to Backend Routes

For each API client HTTP call, find the matching Express route:

```bash
echo "=== BACKEND ROUTES ==="
# List all route definitions
grep -rn "router\.\(get\|post\|put\|patch\|delete\)" \
  "C:\Users\MichaelKunz\Documents\fleetmanager-reservations\backend\src\routes" \
  --include="*.js"
```

### Step 5: Follow Routes to Services

For each route handler, identify the service function called:

```bash
echo "=== SERVICE CALLS FROM ROUTES ==="
grep -rn "Service\.\|service\." \
  "C:\Users\MichaelKunz\Documents\fleetmanager-reservations\backend\src\routes" \
  --include="*.js" | head -30
```

### Step 6: Verify Service → Database

For each service function, check Prisma calls against the schema:

```bash
echo "=== PRISMA CALLS IN SERVICES ==="
grep -rn "prisma\.\w\+\.\(find\|create\|update\|delete\|upsert\|count\|aggregate\)" \
  "C:\Users\MichaelKunz\Documents\fleetmanager-reservations\backend\src\services" \
  --include="*.js" | head -30
```

### Step 7: Deep Trace (Use traceability-reviewer agent)

After the automated scans above, invoke the `traceability-reviewer` agent for deep analysis:

```
Use the traceability-reviewer agent to perform a comprehensive call chain review
of the changed files. Trace every UI action through all layers and verify
signatures, arguments, and return values match at every boundary.
```

The agent will:
1. Read each changed file thoroughly
2. Follow every call from UI → hook → API → route → service → Prisma
3. Verify the return path: DB result → service return → route response → API client → UI rendering
4. Report mismatches with exact file:line references and fixes

---

## Output Format

```markdown
# Traceability Review Results

**Scope**: [files reviewed]
**Chains Traced**: [count]
**Date**: [date]

---

## Call Chain Matrix

| # | UI Action | API Function | HTTP Call | Route | Service Fn | DB Operation | Status |
|---|-----------|--------------|-----------|-------|------------|--------------|--------|
| 1 | ... | ... | ... | ... | ... | ... | ✅/⚠️/❌ |

---

## Critical Issues (Block Deployment)

### [Issue Title]
- **Chain**: [UI] → [API] → [Route] → [Service]
- **Break Point**: [exact layer where it breaks]
- **File**: [path:line]
- **Problem**: [what's wrong]
- **Fix**: [specific change]

---

## Major Issues (Should Fix)

### [Issue Title]
...

---

## Minor Issues (Track)

### [Issue Title]
...

---

## Verified Chains (Passing)

- ✅ [brief description of each verified chain]

---

## Verdict

[ ] **PASS** — All chains verified
[x] **FAIL** — Fix [N] critical, [N] major issues before shipping
```

---

## Severity Criteria

### Critical (Blocks Deployment)
- Function called that doesn't exist
- Wrong number of arguments passed
- Required parameter missing (route expects `fleetId`, client doesn't send it)
- HTTP method mismatch (client sends GET, route only accepts POST)
- URL path mismatch (no matching route)
- Prisma field name doesn't exist in schema
- UI accesses response field that route doesn't return

### Major (Should Fix)
- Type coercion risk (string where number expected)
- Missing error handling at layer boundary
- Unprotected route (missing auth middleware)
- Inconsistent field naming across layers

### Minor (Track)
- Unused function parameters
- Over-fetching (Prisma includes unused relations)
- Redundant validation across layers

---

## Integration

This skill is part of the deployment pipeline:

```
/letsbuild → develop → /pre-deploy → /traceability-review → /shipit
```

For deeper analysis, invoke the `traceability-reviewer` agent:

```
Use the traceability-reviewer agent to perform a thorough review of these changes.
```
