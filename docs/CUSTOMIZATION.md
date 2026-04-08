# Customization Guide

## The Addon Pattern

Platform skills ship with generic checklists. Your project-specific requirements go in **addon files** — separate markdown files that skills read automatically.

This means:
- Platform updates merge cleanly (you never modify platform skill files)
- Your project checks are additive, not replacements
- Multiple teams can share the platform with different addons

## Creating Addon Files

### Code Review Addons

Create `.claude/code-review-addons.md`:

```markdown
## Security (Critical)
- [ ] All customer PII encrypted with encryptionService
- [ ] Searchable fields have HMAC hashes
- [ ] License data deleted after rental period

## Framework Standards
- [ ] Business logic in services/ (not routes/)
- [ ] Use asyncHandler wrapper on all Express routes
- [ ] Prisma includes for related data (no N+1)

## Domain Rules
- [ ] Bikes assigned by specific bikeId (never generic)
- [ ] All dates in UTC ISO format
```

### Security Review Addons

Create `.claude/security-review-addons.md`:

```markdown
## Encryption Requirements
- [ ] AES-256-GCM for PII (name, email, phone)
- [ ] Separate key for license data
- [ ] HMAC-SHA256 for searchable hashes

## Compliance
- [ ] GDPR: Right to deletion implemented
- [ ] PCI-DSS: No card numbers stored

## Multi-Tenant Isolation
- [ ] All queries filtered by tenantId
- [ ] JWT tokens carry tenant array
- [ ] No cross-tenant data leakage possible
```

### Other Addon Files

| File | Purpose |
|------|---------|
| `.claude/api-review-addons.md` | ORM patterns, multi-tenant scoping, middleware conventions |
| `.claude/pre-deploy-addons.md` | Infrastructure checks, cloud provider specifics, CI/CD validation |
| `.claude/perf-test-addons.md` | Benchmark thresholds, specific endpoints, rate limiter config |
| `.claude/deploy-verifier-addons.md` | Health check details, cross-service access, schema validation |

## Adding Custom Skills

Create a new directory in `.claude/skills/your-skill/` with a `SKILL.md` file:

```markdown
---
name: your-skill
description: What it does and when to use it.
user_invocable: true
---

# Your Skill Name

## When to Use
- ...

## Workflow
1. ...
2. ...
```

The skill is automatically available as `/your-skill` in Claude Code.

## Adding Custom Agents

Create a new file in `.claude/agents/your-agent.md`:

```markdown
---
name: your-agent
description: What it does.
model: sonnet
---

# Your Agent

Instructions for the agent...
```

## Modifying Hooks

### Adding a New Hook

1. Create the script in `.claude/hooks/your-hook.sh`
2. Source the shared utilities:
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
   source "$SCRIPT_DIR/_parse-input.sh"
   ```
3. Register it in `.claude/settings.json` under the appropriate event

### Changing Protected Branches

Edit `platform.config.json`:
```json
"branches": {
  "protected": ["main", "staging", "develop"]
}
```

Hooks read this at runtime — no need to modify hook scripts.

## Modifying Permissions

### Project-Level (Shared)

Edit `.claude/settings.json` `permissions.allow` and `permissions.deny` arrays.

### Personal Overrides

Edit `.claude/settings.local.json` (gitignored):
```json
{
  "permissions": {
    "allow": ["Bash(git push origin *)"]
  }
}
```

## Session Conservation Tuning

Edit the thresholds in `.claude/hooks/session-tracker.sh`:
- Line with `50)` — first warning
- Line with `80)` — strong recommendation
- Line with `120)` — critical alert
