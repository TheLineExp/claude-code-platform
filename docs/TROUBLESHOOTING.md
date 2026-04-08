# Troubleshooting

## Hooks Not Firing

**Symptom:** Claude commits to a protected branch or skips checks.

**Fix:**
```bash
# Verify Claude hooks are registered
cat .claude/settings.json | grep "PreToolUse" -A 30

# Verify hook files are executable
ls -la .claude/hooks/*.sh

# Make executable if needed
chmod +x .claude/hooks/*.sh
```

## "BLOCKED: File is inside the main repo"

**Symptom:** Can't edit files even though you should be working.

**Cause:** You're editing in the main repo checkout instead of a worktree.

**Fix:** Run `/letsbuild` to create a worktree, then open Claude Code at the worktree path.

## "BLOCKED: Branch not registered in active-work.md"

**Symptom:** Can't commit on your feature branch.

**Fix:** Add your branch to `.claude/active-work.md`:
```
| w1 | feature/w1-your-branch | ../my-project-w1 | description | 2026-01-01 |
```

Or run `/letsbuild` which does this automatically.

## Git Hooks Not Installed

**Symptom:** Commits succeed on protected branches (pre-commit not running).

**Fix:**
```bash
bash hooks/install.sh

# Verify
bash hooks/verify.sh
```

## Hook Drift (Installed != Template)

**Symptom:** `bash hooks/verify.sh` reports drift.

**Fix:**
```bash
bash hooks/install.sh  # Re-copies from templates
```

## Session Tracker Warnings

**Symptom:** Claude says "session is getting large" or "open a new window."

**This is working as intended.** The session-tracker counts tool calls and warns at thresholds. When you see these warnings:
1. Commit and push your current work
2. Open a new Claude Code window
3. The counter resets with each new session

## One-Try Rule Triggering

**Symptom:** Claude says "ONE-TRY RULE: This error was already encountered."

**This is working as intended.** The error-handler prevents Claude from spinning on the same error. When you see this:
1. Read Claude's explanation of what failed
2. Fix the issue manually (e.g., start Docker, fix env var)
3. Ask Claude to retry

To reset the one-try tracker (if you've fixed the underlying issue):
```bash
rm /tmp/claude-errors-*.log
```

## Windows Path Issues

**Symptom:** Hooks fail with path comparison errors on Windows.

**Fix:** The `enforce-worktree.sh` hook handles Windows path normalization (`C:\` → `/c/`). If you encounter issues:
1. Ensure you're using Git Bash, not PowerShell
2. Check that `git rev-parse --show-toplevel` returns a valid path
3. Verify the normalize function in enforce-worktree.sh handles your path format

## Permission Prompts Still Appearing

**Symptom:** Claude asks for approval on operations that should be auto-approved.

**Check:**
1. Verify `.claude/settings.json` has `permissions.allow` rules
2. Ensure the command pattern matches — `Bash(npm *)` requires a space after `npm`
3. Check for deny rules that might override allow rules
4. Verify `.claude/settings.local.json` exists if you need personal overrides

## platform.config.json Not Found

**Symptom:** Hooks fall back to defaults, branch names don't match.

**Fix:** Run `bash setup.sh` to regenerate, or create manually:
```json
{
  "project": { "name": "my-project", "repoDir": "my-project" },
  "branches": { "production": "main", "staging": "staging", "protected": ["main", "staging"] }
}
```
