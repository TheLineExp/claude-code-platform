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

# --- Quote-blanked command + git command segments (audit A1/A9) ---
# Guards must NEVER match the raw command string: a `^git` anchor lets
# `cd wt && git push` slip through (A1), while grepping the whole string blocks
# innocent commands whose -m/-F/echo arguments merely CONTAIN a flag literal (A9).
#
# COMMAND_NOSTR is COMMAND with quoted strings NORMALIZED: a quoted string that
# is a single safe word is replaced by its bare content — the shell hands
# `git commit "--no-verify"` to git as a plain flag token, so guards must still
# see it (PR #11 review P1). Anything else (spaces, separators, expansions) is
# blanked to "", so a commit message or echo argument that merely CONTAINS a
# flag literal can never trip a guard (audit A9). Partial quoting concatenates
# (`--no-ver"ify"` → `--no-verify`), matching shell word-joining.
# Leftmost-first alternation mirrors shell quote scanning closely enough.
COMMAND_NOSTR=$(printf '%s' "$COMMAND" | perl -0777 -pe '
  s{"((?:[^"\\]|\\.)*)"|\x27([^\x27]*)\x27}{
    my $c = defined $1 ? $1 : $2;
    $c =~ s/\\(.)/$1/g if defined $1;
    $c =~ m{^[A-Za-z0-9_+.,:\/=\@^~*-]+$} ? $c : q("")
  }ge' 2>/dev/null)

# GIT_SEGMENTS: one line per simple command that IS a git/gh invocation. The raw
# command is split on separators (;, &&, ||, |, &, newline, $(, `, subshell/group
# openers) OUTSIDE quotes; each segment is stripped of leading env assignments
# (VAR=1 git …) and common wrappers (sudo/command/env/…), and git/gh global
# options before the subcommand (-C dir, -c k=v, --no-pager, -R owner/repo) are
# dropped so `git -C . push` still reads as `git push`. Hooks anchor their
# patterns to `^git <subcommand>` against THESE lines, never against $COMMAND.
_git_segments() {
  printf '%s' "$COMMAND_NOSTR" | perl -0777 -ne '
    for my $seg (split /\|\||&&|[;|&\n(]|\$\(|`|\{[[:space:]]/) {
      $seg =~ s/^\s+//;
      1 while $seg =~ s/^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+|sudo\s+|command\s+|builtin\s+|nohup\s+|time\s+|env\s+)//;
      next unless $seg =~ /^(?:git|gh)(?:\s|$)/;
      1 while $seg =~ s/^(git|gh)\s+(?:-[Cc]\s+\S+|-R\s+\S+|--(?:repo|git-dir|work-tree|namespace|exec-path)(?:=\S+|\s+\S+)?|--no-pager|--paginate|--bare|--literal-pathspecs)\s+/$1 /;
      print "$seg\n";
    }' 2>/dev/null
}

# --- Fast-path optimization ---
# Most Bash commands (ls, cat, grep, npm, node) don't need git-safety checks.
# NEEDS_GIT_CHECK is true only when a REAL git/gh command segment exists (a git
# literal inside quotes no longer counts). NEEDS_FILE_CHECK is true for redirects
# AND for the non-redirect writers block-file-redirect.sh inspects (audit A7).

NEEDS_GIT_CHECK=false
NEEDS_FILE_CHECK=false
GIT_SEGMENTS=""

if [ -n "$COMMAND" ]; then
  # Cheap pre-grep before spawning perl for segmentation.
  if echo "$COMMAND" | grep -qE '(^|[^[:alnum:]_.-])(git|gh)([[:space:]]|$)'; then
    GIT_SEGMENTS=$(_git_segments)
    [ -n "$GIT_SEGMENTS" ] && NEEDS_GIT_CHECK=true
  fi
  # Redirect detection: `>`/`>>`/`>|` followed by an eventual filename, WITH or
  # WITHOUT a space (`>foo` and `> foo` both redirect). Exclude fd-dup forms
  # (`>&`, `2>&1`) — the next char after `>` there is `&`, not a file. Also flag
  # the non-redirect writers (sed -i, cp, mv, dd, sponge — audit A7). This is
  # only a fast-path gate; block-file-redirect.sh does the precise check.
  if echo "$COMMAND" | grep -qE '(>[>|]?[[:space:]]*[^&|>[:space:]]|\btee\b|(^|[^[:alnum:]_.-])(sed|cp|mv|dd|sponge)([[:space:]]|$))'; then
    NEEDS_FILE_CHECK=true
  fi
fi

# Is the letsbuild multi-agent workflow ACTIVE in this repo? The worktree-discipline
# hooks (enforce-worktree, check-work-registration, check-branch-prefix, block-file-redirect)
# are deployed GLOBALLY but must only enforce where the workflow is set up — signalled by a
# registered row in .claude/active-work.md (a `| wX | … |` / `| xN | … |` / `| s | … |`
# line). Repos without registered work (the platform repo, one-off checkouts) → no-op.
# Only the worktree hooks call this; universal git guards ignore it and run everywhere.
_fleet_active() {
  local gcd main tl d
  gcd=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$gcd" in
    /*) main=$(dirname "$gcd") ;;
    *)  main=$(cd "$(dirname "$gcd")" 2>/dev/null && pwd) ;;
  esac
  tl=$(git rev-parse --show-toplevel 2>/dev/null)
  for d in "$tl" "$main"; do
    [ -n "$d" ] && [ -f "$d/.claude/active-work.md" ] && \
      grep -qE '^\|[[:space:]]*(w|x|s)[0-9]*[[:space:]]*\|' "$d/.claude/active-work.md" && return 0
  done
  return 1
}

# Fleet-SHAPED repo: a .claude/ directory exists in the worktree or main checkout.
# block-protected-branch gates on THIS, not on _fleet_active — deploy-branch
# protection must fail CLOSED (audit A8: an emptied/corrupted active-work.md made
# every fleet guard no-op, allowing a direct push to master). Worktree-discipline
# hooks still gate on _fleet_active, because registration is what signals that the
# letsbuild workflow is actually running.
_fleet_shaped() {
  local gcd main tl d
  gcd=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$gcd" in
    /*) main=$(dirname "$gcd") ;;
    *)  main=$(cd "$(dirname "$gcd")" 2>/dev/null && pwd) ;;
  esac
  tl=$(git rev-parse --show-toplevel 2>/dev/null)
  for d in "$tl" "$main"; do
    [ -n "$d" ] && [ -d "$d/.claude" ] && return 0
  done
  return 1
}
