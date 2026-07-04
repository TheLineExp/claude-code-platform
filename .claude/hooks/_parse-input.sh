#!/bin/bash
# Shared JSON input parser for Claude Code PreToolUse hooks.
# Reads stdin once and extracts the command string.
# Includes fast-path exit for non-relevant commands.
#
# Usage: source "$(dirname "$0")/_parse-input.sh"
# After sourcing, $INPUT contains the full JSON and $COMMAND contains the command string.
# If the command is irrelevant to the hook, the script exits 0 (allow).

INPUT=$(cat)

# Extract command from JSON, correctly handling escaped quotes/backslashes
# (`echo "hi" > f` arrives as `"command":"echo \"hi\" > f"` — a naive `[^"]*`
# stops at the first \" and truncates the command before the redirect). Perl
# parses the JSON string value with escapes; fall back to a greedy sed if perl
# is somehow absent (worst case COMMAND is empty → hooks fast-path allow).
COMMAND=$(printf '%s' "$INPUT" | perl -0777 -ne 'if(/"command"\s*:\s*"((?:[^"\\]|\\.)*)"/s){my $c=$1; $c=~s/\\(["\\\/])/$1/g; $c=~s/\\n/\n/g; $c=~s/\\t/\t/g; print $c}' 2>/dev/null)
if [ -z "$COMMAND" ] && echo "$INPUT" | grep -q '"command"'; then
  COMMAND=$(echo "$INPUT" | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"(.*)".*/\1/' | sed 's/\\"/"/g')
fi

# Extract file_path for Edit/Write hooks: {"file_path": "/path/to/file"} → /path/to/file
FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# --- Fast-path optimization ---
# Most Bash commands (ls, cat, grep, npm, node) don't need git-safety checks.
# Set NEEDS_GIT_CHECK=true only for git/gh commands.
# Set NEEDS_FILE_CHECK=true only for commands that write to files via redirects.

NEEDS_GIT_CHECK=false
NEEDS_FILE_CHECK=false

if [ -n "$COMMAND" ]; then
  # git/gh anywhere as a command word — NOT just at the start. `cd x && git push`,
  # `VAR=1 gh pr merge`, `sudo git …` must all trip the git guards. Over-matching is
  # safe: the downstream hooks each do their own precise check. (Preceded by start or
  # a separator, not an identifier char, so `mygit`/`night` don't match.)
  if echo "$COMMAND" | grep -qE '(^|[^[:alnum:]_.-])(git|gh)[[:space:]]'; then
    NEEDS_GIT_CHECK=true
  fi
  # Redirect detection: `>`/`>>` followed by an eventual filename, WITH or
  # WITHOUT a space (`>foo` and `> foo` both redirect). Exclude fd-dup forms
  # (`>&`, `2>&1`) — the next char after `>` there is `&`, not a file. This is
  # only a fast-path gate; block-file-redirect.sh does the precise check.
  if echo "$COMMAND" | grep -qE '(>>?[[:space:]]*[^&|>[:space:]]|\btee\b)'; then
    NEEDS_FILE_CHECK=true
  fi
fi
