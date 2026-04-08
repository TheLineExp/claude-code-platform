#!/bin/bash
# Fires on PreCompact — context is about to be compressed.
# Injects a reminder to Claude about critical platform rules that might
# get lost during compaction, and suggests a new window.
#
# This is the strongest signal that context is exhausted.

INPUT=$(cat)

# Detect if this is auto-compaction (context full) vs manual (/compact)
TRIGGER=$(echo "$INPUT" | grep -o '"trigger"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"trigger"[[:space:]]*:[[:space:]]*"//;s/"$//')

if [ "$TRIGGER" = "auto" ]; then
  echo "" >&2
  echo "=== CONTEXT COMPACTION OCCURRING ===" >&2
  echo "The conversation context is being compressed because it reached capacity." >&2
  echo "" >&2
  echo "CRITICAL RULES TO PRESERVE:" >&2
  echo "1. NEVER commit to protected branches — use feature branches" >&2
  echo "2. NEVER merge PRs — only the user merges" >&2
  echo "3. All code edits must happen in a worktree, not the main repo" >&2
  echo "4. Read platform.config.json for project settings" >&2
  echo "" >&2
  echo "TELL THE USER: 'Context was just compressed — some earlier details may be lost." >&2
  echo "I recommend opening a new Claude Code window if you're starting a new task.'" >&2
  echo "=== END COMPACTION NOTICE ===" >&2
fi

exit 0
