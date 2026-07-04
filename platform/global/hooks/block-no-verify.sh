#!/bin/bash
# Block --no-verify flag on any command. Hooks must always run.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

if echo "$COMMAND" | grep -qE '\-\-no-verify'; then
  echo "BLOCKED: --no-verify is not allowed. All hooks must run." >&2
  echo "If a hook is failing, fix the underlying issue instead of bypassing it." >&2
  exit 2
fi

exit 0
