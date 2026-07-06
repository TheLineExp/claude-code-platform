#!/bin/bash
# Shared JSON input parser for Claude Code PreToolUse hooks.
# Reads stdin once, extracts the command, and runs the ONE shell-faithful
# tokenizer (_tokenize.pl) so every guard matches on a normalized ARGV MODEL
# rather than regex against a command string.
#
# Usage: source "$(dirname "$0")/_parse-input.sh"
# After sourcing:
#   $COMMAND           the decoded command string
#   $FILE_PATH         the Edit/Write file_path (if any)
#   $NEEDS_GIT_CHECK   true iff some simple-command's argv0 is git/gh
#   $NEEDS_FILE_CHECK  true iff some command writes (writer argv0 or a redirect)
#   _for_each_command <fn>   invokes <fn> per simple-command with globals set:
#                       CMD_ARGV[]  (argv tokens, quotes already resolved)
#                       CMD_EFFDIR  (cd-/`git -C`-tracked effective directory)
#                       CMD_REDIRS[] (write-redirect targets)
#   _first_effdir <subcmd>   effdir of the first `git <subcmd>` command (else .)
#   _resolve_dir / _fleet_active / _fleet_shaped   (unchanged helpers)
#
# WHY the argv model (2026-07-05 pivot): the guards used to regex a command
# STRING and there were TWO drifting parsers. A quoted `-m` message that merely
# CONTAINS `--no-verify` (audit A9) is now exactly ONE argv token a guard skips,
# and the writer/git surfaces share ONE tokenizer, so parity is structural.

INPUT=$(cat)

# Extract command from JSON, correctly handling escaped quotes/backslashes.
COMMAND=$(printf '%s' "$INPUT" | perl -0777 -ne 'if(/"command"\s*:\s*"((?:[^"\\]|\\.)*)"/s){my $c=$1; $c=~s/\\(["\\\/])/$1/g; $c=~s/\\n/\n/g; $c=~s/\\t/\t/g; print $c}' 2>/dev/null)
if [ -z "$COMMAND" ] && echo "$INPUT" | grep -q '"command"'; then
  COMMAND=$(echo "$INPUT" | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"(.*)".*/\1/' | sed 's/\\"/"/g')
fi

# Extract file_path for Edit/Write hooks.
FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# --- Tokenize (once) into the argv model ---
# Cheap pre-grep first: only spawn the tokenizer when the command plausibly
# contains a guarded verb or a redirect. Quote/escape characters are STRIPPED
# before the grep, because quoting can split a command word so its letters are
# not contiguous (`c"p"`, `g"it"`, `\git`) — grepping the raw string would miss
# them (the leak the old code avoided by normalizing first). Stripping only makes
# the gate MORE permissive, so it can over-tokenize a harmless `echo "git"` but
# never under-detect a real invocation the way a `^git` anchor did (audit A1).
NEEDS_GIT_CHECK=false
NEEDS_FILE_CHECK=false
_TOKENIZED=""
# Heredoc BODIES are stdin DATA, never shell commands. They are consumed INSIDE the
# tokenizer (_tokenize.pl scan()), which is quote- and comment-aware — so a `<<WORD`
# is treated as a heredoc opener ONLY in true operator position (never inside quotes
# or after a `#`). That kills BOTH failure modes with ONE parser: the A9 false-POSITIVE
# (a `git commit -F- <<EOF` message body quoting `git push --force` no longer reads as a
# command) AND the quoted/commented-`<<WORD` false-NEGATIVE (a fake opener no longer
# queues a phantom delimiter that swallows the real commands after it). The old
# line-based regex pre-strip lived HERE and was exactly the "second hand-maintained
# parser" the tokenizer rewrite exists to eliminate — deleted, not patched.
_CMD_TOK="$COMMAND"
_CMD_BARE=$(printf '%s' "$_CMD_TOK" | tr -d '\042\047\134')   # drop " ' \
if [ -n "$COMMAND" ] && printf '%s' "$_CMD_BARE" | grep -qE '(^|[^[:alnum:]_.-])(git|gh|sed|cp|mv|dd|sponge|tee)([^[:alnum:]_.-]|$)|>'; then
  _TOKENIZED=$(printf '%s' "$_CMD_TOK" | perl "$SCRIPT_DIR/_tokenize.pl" 2>/dev/null)
  if [ -n "$_TOKENIZED" ]; then
    echo "$_TOKENIZED" | grep -qE '^C(git|gh)$' && NEEDS_GIT_CHECK=true
    if echo "$_TOKENIZED" | grep -qE '^C(sed|cp|mv|dd|sponge|tee)$' || echo "$_TOKENIZED" | grep -q '^R'; then
      NEEDS_FILE_CHECK=true
    fi
  fi
fi

# Walk the tokenized model, invoking <fn> once per simple-command with CMD_ARGV /
# CMD_EFFDIR / CMD_REDIRS populated. The loop runs in the CURRENT shell (a
# here-string, not a pipe), so a callback may `exit 2` to block, and array
# assignments persist. argv tokens are used verbatim — no re-splitting — so a
# token with spaces (a quoted message, a `git -C "/a b"` path) stays intact.
_for_each_command() {
  local _cb="$1" _line _key _val _have=0
  CMD_ARGV=(); CMD_EFFDIR="."; CMD_REDIRS=()
  while IFS= read -r _line; do
    _key=${_line:0:1}; _val=${_line:1}
    case "$_key" in
      C) [ "$_have" = 1 ] && "$_cb"
         CMD_ARGV=(); CMD_EFFDIR="."; CMD_REDIRS=(); _have=1 ;;
      D) CMD_EFFDIR="$_val" ;;
      A) CMD_ARGV+=("$_val") ;;
      R) CMD_REDIRS+=("$_val") ;;
    esac
  done <<< "$_TOKENIZED"
  [ "$_have" = 1 ] && "$_cb"
}

# _first_effdir <subcmd>: the effdir of the first git command whose subcommand
# matches (so `git -C <path> commit` resolves branch/registration at <path>).
_first_effdir() {
  printf '%s\n' "$_TOKENIZED" | awk -v want="$1" '
    /^C/ { a0 = substr($0,2); n=0; d="."; iscmd=(a0=="git") }
    /^D/ { d = substr($0,2) }
    /^A/ { n++; if (iscmd && n==2 && substr($0,2)==want) { print d; exit } }
  '
}

# _resolve_dir <candidate>: echo it if it is a real git worktree, else `.` (the
# hook cwd). A cd/-C target that does not resolve — bogus, nonexistent, or not a
# repo — must NOT disable the guard (fail toward the current repo; PR #11 R7).
_resolve_dir() {
  local d="${1:-.}"
  if [ "$d" != "." ] && git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    printf '%s' "$d"
  else
    printf '.'
  fi
}

# Is the letsbuild multi-agent workflow ACTIVE here? Worktree-discipline hooks
# (enforce-worktree, check-work-registration, check-branch-prefix,
# block-file-redirect) deploy globally but only enforce where a row is registered
# in .claude/active-work.md. Universal git guards ignore this and run everywhere.
_fleet_active() {
  local at="${1:-.}" gcd main tl d
  gcd=$(git -C "$at" rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$gcd" in
    /*) main=$(dirname "$gcd") ;;
    *)  main=$(cd "$at" 2>/dev/null && cd "$(dirname "$gcd")" 2>/dev/null && pwd) ;;
  esac
  tl=$(git -C "$at" rev-parse --show-toplevel 2>/dev/null)
  for d in "$tl" "$main"; do
    [ -n "$d" ] && [ -f "$d/.claude/active-work.md" ] && \
      grep -qE '^\|[[:space:]]*(w|x|s)[0-9]*[[:space:]]*\|' "$d/.claude/active-work.md" && return 0
  done
  return 1
}

# Fleet-SHAPED repo: a .claude/ dir exists in the worktree or main checkout.
# block-protected-branch gates on THIS, not _fleet_active — deploy-branch
# protection must fail CLOSED even if active-work.md is emptied (audit A8).
_fleet_shaped() {
  local at="${1:-.}" gcd main tl d
  gcd=$(git -C "$at" rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$gcd" in
    /*) main=$(dirname "$gcd") ;;
    *)  main=$(cd "$at" 2>/dev/null && cd "$(dirname "$gcd")" 2>/dev/null && pwd) ;;
  esac
  tl=$(git -C "$at" rev-parse --show-toplevel 2>/dev/null)
  for d in "$tl" "$main"; do
    [ -n "$d" ] && [ -d "$d/.claude" ] && return 0
  done
  return 1
}
