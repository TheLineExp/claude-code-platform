---
name: code-review
description: Comprehensive code review skill. Triggers after completing coding tasks, implementing features, or fixing bugs. Ensures code is clean, efficient, secure, and follows project standards. Supports project-specific addons.
user_invocable: true
---

# Code Review Skill

Reviews all code changes for quality, security, and efficiency before commit or deploy.

## When to Use

- After implementing any new feature or fixing bugs
- Before committing changes
- When the user asks to "review", "check", or "validate" code

## Review Process

### Step 1: Gather Context

```bash
git diff --stat HEAD
git diff --name-only HEAD
git log --oneline -5
```

### Step 2: Apply Generic Checklist

#### Security (Critical)
- [ ] No hardcoded secrets, API keys, or passwords
- [ ] Input validation on all user-facing endpoints
- [ ] Authentication required on protected routes
- [ ] Authorization checks for resource access
- [ ] No SQL injection vulnerabilities (parameterized queries)
- [ ] No XSS vulnerabilities (output encoding)
- [ ] Rate limiting on sensitive endpoints
- [ ] Audit logging for sensitive operations

#### Performance
- [ ] No N+1 database queries (use eager loading / includes)
- [ ] Independent async operations use `Promise.all()` / gather
- [ ] Large datasets use pagination
- [ ] Frequently-queried fields have database indexes
- [ ] No blocking operations in request handlers

#### Code Quality
- [ ] Business logic in services/domain layer (not route handlers)
- [ ] Functions have single responsibility
- [ ] No duplicated code
- [ ] Meaningful variable and function names
- [ ] Proper error handling with try/catch
- [ ] No debug console.log/print statements left in
- [ ] No commented-out code blocks

#### Architecture
- [ ] Follows existing patterns in the codebase
- [ ] New dependencies justified and necessary
- [ ] Configuration via environment variables (not hardcoded)
- [ ] Tests added for new functionality

### Step 3: Apply Project-Specific Checklist

**Read `.claude/code-review-addons.md` if it exists.** Apply every check from that file in addition to the generic checks above. This file contains project-specific security patterns, framework conventions, and domain-specific rules.

If the file does not exist, skip this step.

### Step 4: Output Format

Categorize findings as:

- **CRITICAL**: Security issues, data leaks, auth bypass — must fix immediately
- **MAJOR**: Performance problems, code quality issues — should fix before merge
- **MINOR**: Style, documentation — nice to have

### Step 5: Integration

For deeper analysis, invoke the `code-reviewer` agent:

```
Use the code-reviewer agent to perform a thorough review of these changes.
```
