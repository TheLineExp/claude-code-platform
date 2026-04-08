#!/bin/bash
# Session tracker — counts tool calls as a proxy for context size.
# Runs on PostToolUse to increment a counter.
# At thresholds, injects guidance via stderr that Claude sees.
#
# Thresholds:
#   50 calls  — "Consider wrapping up this task"
#   80 calls  — "Session is getting long — suggest opening a new window"
#   120 calls — "Critical: context compression likely, open new window now"
#
# Counter stored in /tmp/claude-session-<ppid>.count
# Reset when a new session starts (different PPID)

COUNTER_FILE="/tmp/claude-session-${PPID}.count"

# Read or initialize counter
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
else
  COUNT=0
fi

# Increment
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Threshold guidance (output to stderr so Claude sees it)
case "$COUNT" in
  50)
    echo "" >&2
    echo "SESSION NOTE: 50 tool calls in this session. Consider wrapping up the current task and committing progress." >&2
    echo "If starting a new topic, suggest opening a fresh Claude Code window for better context efficiency." >&2
    ;;
  80)
    echo "" >&2
    echo "SESSION WARNING: 80 tool calls — session context is growing large." >&2
    echo "RECOMMEND: Finish current work, commit changes, then tell the user:" >&2
    echo "  'This session has been productive but the context is getting large." >&2
    echo "   I recommend opening a new Claude Code window for the next task" >&2
    echo "   to keep responses fast and accurate.'" >&2
    ;;
  120)
    echo "" >&2
    echo "SESSION CRITICAL: 120 tool calls — context compression is likely occurring." >&2
    echo "STRONGLY RECOMMEND opening a new window. Earlier context may be lost." >&2
    echo "Tell the user: 'We should wrap up here — the session context is at capacity." >&2
    echo "Please open a new Claude Code window for continued work.'" >&2
    ;;
esac

exit 0
