#!/bin/bash
# PostToolUseFailure hook — detects configuration errors and suggests fixes.
# Implements the "one try" rule: if Claude already tried and failed on the
# same error, don't retry — escalate to the user immediately.
#
# The hook:
#   1. Reads the failed tool output
#   2. Checks if this is a known configuration error pattern
#   3. If it's a NEW error (not seen this session), provides fix guidance
#   4. If it's a REPEATED error (already tried once), blocks retry and escalates
#
# Error tracking stored in /tmp/claude-errors-<ppid>.log

INPUT=$(cat)
ERROR_LOG="/tmp/claude-errors-${PPID}.log"

# Extract error details
TOOL_NAME=$(echo "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"//;s/"$//')
COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
STDERR=$(echo "$INPUT" | grep -o '"stderr"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"stderr"[[:space:]]*:[[:space:]]*"//;s/"$//')
STDOUT=$(echo "$INPUT" | grep -o '"stdout"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"stdout"[[:space:]]*:[[:space:]]*"//;s/"$//')
ERROR_TEXT="$STDERR $STDOUT"

# Create a fingerprint for this error (tool + first 80 chars of error)
ERROR_FINGERPRINT="${TOOL_NAME}:$(echo "$ERROR_TEXT" | head -c 80 | tr ' \n' '__')"

# Check if we've seen this error before in this session
if [ -f "$ERROR_LOG" ] && grep -qF "$ERROR_FINGERPRINT" "$ERROR_LOG"; then
  # REPEATED ERROR — escalate, don't retry
  echo "" >&2
  echo "ONE-TRY RULE: This error was already encountered in this session." >&2
  echo "DO NOT retry the same approach. Instead:" >&2
  echo "1. Tell the user what failed and why" >&2
  echo "2. Ask the user how they'd like to proceed" >&2
  echo "3. If it's a configuration issue, suggest specific manual steps" >&2
  echo "" >&2
  echo "Previous attempt did not resolve this. Escalate to user." >&2
  exit 0
fi

# Log this error (first occurrence)
echo "$ERROR_FINGERPRINT" >> "$ERROR_LOG"

# --- Pattern matching for known configuration errors ---

# Pattern: Missing environment variable
if echo "$ERROR_TEXT" | grep -qiE 'env.*not (set|defined|found)|missing.*env|undefined.*variable|ENOENT.*\.env'; then
  echo "" >&2
  echo "CONFIG ERROR DETECTED: Missing environment variable or .env file." >&2
  echo "FIX: Check .env.example for required variables, or run the setup wizard." >&2
  echo "Launch the error-fixer agent to diagnose and suggest a fix." >&2
  exit 0
fi

# Pattern: Permission denied / access error
if echo "$ERROR_TEXT" | grep -qiE 'permission denied|EACCES|access denied|not authorized'; then
  echo "" >&2
  echo "CONFIG ERROR DETECTED: Permission or access issue." >&2
  echo "FIX: Check file permissions, authentication tokens, or database grants." >&2
  echo "Launch the error-fixer agent to diagnose." >&2
  exit 0
fi

# Pattern: Module/package not found
if echo "$ERROR_TEXT" | grep -qiE 'cannot find module|ModuleNotFoundError|No module named|package.*not found|ENOENT.*node_modules'; then
  echo "" >&2
  echo "CONFIG ERROR DETECTED: Missing dependency or module." >&2
  echo "FIX: Run 'npm install' or check package.json. Dependencies may not be installed." >&2
  exit 0
fi

# Pattern: Port already in use
if echo "$ERROR_TEXT" | grep -qiE 'EADDRINUSE|address already in use|port.*already.*bound'; then
  echo "" >&2
  echo "CONFIG ERROR DETECTED: Port already in use." >&2
  echo "FIX: Kill the existing process or use a different port." >&2
  exit 0
fi

# Pattern: Database connection failure
if echo "$ERROR_TEXT" | grep -qiE 'ECONNREFUSED|connection refused|database.*not.*running|no pg_hba.conf entry|authentication failed.*role'; then
  echo "" >&2
  echo "CONFIG ERROR DETECTED: Database connection failure." >&2
  echo "FIX: Check if the database is running, verify connection string, check credentials." >&2
  echo "Launch the error-fixer agent to diagnose." >&2
  exit 0
fi

# Pattern: Docker not running
if echo "$ERROR_TEXT" | grep -qiE 'docker.*not.*running|cannot connect to.*docker|docker daemon.*not running|Is the docker daemon running'; then
  echo "" >&2
  echo "CONFIG ERROR DETECTED: Docker is not running." >&2
  echo "FIX: Start Docker Desktop, then retry." >&2
  exit 0
fi

# Pattern: Git hook failure (from our own hooks)
if echo "$ERROR_TEXT" | grep -qiE 'BLOCKED:.*commit|BLOCKED:.*push|BLOCKED:.*merge'; then
  echo "" >&2
  echo "HOOK BLOCK: This operation was blocked by a safety hook." >&2
  echo "This is intentional — read the block message above and follow its guidance." >&2
  echo "DO NOT attempt to bypass the hook." >&2
  exit 0
fi

# Pattern: Prisma/migration error
if echo "$ERROR_TEXT" | grep -qiE 'P3009|P3018|prisma.*migrate|migration.*failed|schema.*drift'; then
  echo "" >&2
  echo "CONFIG ERROR DETECTED: Database migration issue." >&2
  echo "FIX: Run repair-migrations.js, then prisma migrate deploy." >&2
  exit 0
fi

# No known pattern matched — let Claude handle it normally
exit 0
