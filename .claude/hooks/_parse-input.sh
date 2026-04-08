#!/bin/bash
# Shared JSON input parser for Claude Code PreToolUse hooks.
# Reads stdin once and extracts the command string.
# Includes fast-path exit for non-relevant commands.
#
# Usage: source "$(dirname "$0")/_parse-input.sh"
# After sourcing, $INPUT contains the full JSON and $COMMAND contains the command string.
# If the command is irrelevant to the hook, the script exits 0 (allow).

INPUT=$(cat)

# Extract command from JSON: {"command": "git status"} → git status
COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"command"[[:space:]]*:[[:space:]]*"//;s/"$//')

# Extract file_path for Edit/Write hooks: {"file_path": "/path/to/file"} → /path/to/file
FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# --- Fast-path optimization ---
# Most Bash commands (ls, cat, grep, npm, node) don't need git-safety checks.
# Set NEEDS_GIT_CHECK=true only for git/gh commands.
# Set NEEDS_FILE_CHECK=true only for commands that write to files via redirects.

NEEDS_GIT_CHECK=false
NEEDS_FILE_CHECK=false

if [ -n "$COMMAND" ]; then
  if echo "$COMMAND" | grep -qE '^(git |gh )'; then
    NEEDS_GIT_CHECK=true
  fi
  if echo "$COMMAND" | grep -qE '(>\s|>>\s|\btee\b)'; then
    NEEDS_FILE_CHECK=true
  fi
fi
