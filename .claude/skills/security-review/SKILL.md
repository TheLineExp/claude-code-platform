---
name: security-review
description: Security audit skill. Focuses on authentication, authorization, input validation, secrets management, and compliance. Supports project-specific security profiles via addons.
user_invocable: true
---

# Security Review Skill

Comprehensive security audit for code changes. Covers OWASP Top 10 and common security anti-patterns.

## When to Use

- After implementing security-sensitive features
- Before deploying to production
- When the user asks for a "security review" or "security audit"

## Review Process

### Step 1: Gather Changed Files

```bash
git diff --name-only HEAD~5..HEAD
git diff --stat HEAD~5..HEAD
```

### Step 2: OWASP Top 10 Checklist

#### 1. Injection
- [ ] All database queries use parameterized statements / ORM
- [ ] No string concatenation in SQL queries
- [ ] No eval() or equivalent with user input
- [ ] Command injection prevented (no shell exec with user input)

#### 2. Broken Authentication
- [ ] Passwords hashed with bcrypt/argon2 (never plaintext/MD5/SHA)
- [ ] JWT tokens validated properly (signature, expiry, issuer)
- [ ] Session management secure (httpOnly, secure, sameSite cookies)
- [ ] Rate limiting on login/auth endpoints

#### 3. Sensitive Data Exposure
- [ ] Sensitive data encrypted at rest
- [ ] HTTPS enforced for all endpoints
- [ ] No sensitive data in logs or error messages
- [ ] No secrets in source code or version control

#### 4. Broken Access Control
- [ ] Authorization checks on every endpoint
- [ ] Multi-tenant isolation (users can't access other tenants' data)
- [ ] RBAC/permission checks enforced
- [ ] No IDOR (insecure direct object references)

#### 5. Security Misconfiguration
- [ ] Security headers set (HSTS, CSP, X-Frame-Options, etc.)
- [ ] CORS configured restrictively
- [ ] Debug mode disabled in production
- [ ] Default credentials not used

#### 6. Cross-Site Scripting (XSS)
- [ ] User input sanitized before rendering
- [ ] Content-Security-Policy header configured
- [ ] No dangerouslySetInnerHTML (or equivalent) with user data

#### 7-10. Additional checks
- [ ] Dependencies scanned for known vulnerabilities
- [ ] File upload validation (type, size, content)
- [ ] API rate limiting configured
- [ ] Error messages don't leak internal details

### Step 3: Apply Project-Specific Security Profile

**Read `.claude/security-review-addons.md` if it exists.** This file contains project-specific security requirements like:
- Custom encryption patterns
- Compliance requirements (GDPR, CCPA, PCI-DSS, HIPAA)
- Domain-specific security rules
- Infrastructure-specific checks

### Step 4: Output Format

```
## Security Review Summary

### CRITICAL (must fix before merge)
- [description, file, line]

### HIGH (should fix before production)
- [description, file, line]

### MEDIUM (fix in next sprint)
- [description, file, line]

### LOW (informational)
- [description]

### Overall Risk: LOW / MEDIUM / HIGH / CRITICAL
```
