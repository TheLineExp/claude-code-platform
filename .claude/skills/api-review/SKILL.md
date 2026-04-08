---
name: api-review
description: REST API design review. Evaluates API design, performance, consistency, documentation, and best practices. Supports project-specific addons.
user_invocable: true
---

# API Review Skill

Reviews API endpoints for RESTful design, performance, consistency, and security.

## When to Use

- After implementing new API endpoints
- When modifying existing API routes
- Before deploying API changes

## Review Checklist

### 1. RESTful Design
- [ ] Proper HTTP methods (GET for reads, POST for creates, PUT/PATCH for updates, DELETE for deletes)
- [ ] Resource-oriented URLs (nouns, not verbs)
- [ ] Consistent URL naming (kebab-case, plural resources)
- [ ] Proper nesting depth (max 2 levels: `/resources/:id/sub-resources`)

### 2. Request/Response Format
- [ ] Consistent JSON structure across endpoints
- [ ] Proper HTTP status codes (200, 201, 204, 400, 401, 403, 404, 409, 422, 500)
- [ ] Error responses include type, message, and field-level details
- [ ] Dates in ISO 8601 UTC format

### 3. Pagination
- [ ] List endpoints support pagination (limit/offset or cursor)
- [ ] Default page size is reasonable (10-50)
- [ ] Response includes total count and next/prev links

### 4. Performance
- [ ] No N+1 queries (use eager loading)
- [ ] Large responses paginated
- [ ] Appropriate cache headers
- [ ] Database indexes for filtered/sorted fields
- [ ] Independent operations parallelized

### 5. Authentication & Authorization
- [ ] All endpoints require authentication (unless explicitly public)
- [ ] Authorization checks for resource access
- [ ] API keys/tokens validated on every request
- [ ] Rate limiting configured per endpoint tier

### 6. Input Validation
- [ ] All input validated and sanitized
- [ ] Required fields enforced
- [ ] Type checking (strings, numbers, UUIDs, dates)
- [ ] Max lengths and bounds enforced

### 7. Documentation
- [ ] Endpoints documented (method, path, params, body, response)
- [ ] Error codes documented
- [ ] Authentication requirements documented

### 8. Apply Project-Specific Checks

**Read `.claude/api-review-addons.md` if it exists.** Apply project-specific API patterns (multi-tenant scoping, ORM patterns, middleware conventions, etc.).

### Output Format

Rate each section 1-5 and provide specific findings:

```
## API Review: [endpoint or feature name]

| Section | Score | Notes |
|---------|-------|-------|
| RESTful Design | 4/5 | ... |
| Request/Response | 5/5 | ... |
| ... | ... | ... |

### Issues Found
- [CRITICAL/MAJOR/MINOR]: description
```
