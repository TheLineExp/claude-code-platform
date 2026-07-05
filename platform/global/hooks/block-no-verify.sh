#!/bin/bash
# Block --no-verify on git commands. Hooks must always run.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# --no-verify only means something on a git command, and matching is per git
# SEGMENT with quoted-string contents blanked — so a commit message that merely
# MENTIONS --no-verify (audit A9, bit twice) or a grep/echo containing the
# literal can never trip this guard.
$NEEDS_GIT_CHECK || exit 0

while IFS= read -r seg; do
  [ -n "$seg" ] || continue

  # Long form, including unambiguous long-option prefixes git also accepts
  # (--no-veri, --no-verif — same defect class as audit A5's `reset --h`).
  if echo "$seg" | grep -qE '(^|[[:space:]])--no-veri(f(y)?)?([[:space:]]|$)'; then
    echo "BLOCKED: --no-verify is not allowed. All hooks must run." >&2
    echo "If a hook is failing, fix the underlying issue instead of bypassing it." >&2
    exit 2
  fi

  # Short form (audit A2): `git commit -n` is --no-verify, including bundled
  # clusters (-an, -nm, -anm). Commit only — `git push -n` is --dry-run and
  # `git merge -n` is --no-stat.
  if echo "$seg" | grep -qE '^git[[:space:]]+commit([[:space:]]|$)' && \
     echo "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
    echo "BLOCKED: 'git commit -n' is --no-verify. All hooks must run." >&2
    echo "If a hook is failing, fix the underlying issue instead of bypassing it." >&2
    exit 2
  fi
done <<< "$GIT_SEGMENTS"

exit 0
