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
# COMMAND_EXEC flattens command-string operands that the shell EXECUTES, so the
# guards analyze the real command, not an opaque quoted blob that blanking would
# erase (PR #11 R4/R5): `env -S "<cmd>"` / `--split-string`, and
# `bash|sh|dash|zsh|ksh -c "<cmd>"`. The dequoted operand replaces the whole
# wrapper run. (A false match inside an echo argument is harmless — it stays a
# non-git word after normalization.) Iterated so a nested `bash -c "env -S …"`
# unwraps fully.
_flatten_exec() {
  perl -0777 -pe '
    sub dq { my $o = shift;
      if    ($o =~ /^"(.*)"$/s)      { $o = $1; $o =~ s/\\(.)/$1/g; }
      elsif ($o =~ /^\x27(.*)\x27$/s){ $o = $1; }
      $o;
    }
    my $n = 0;
    1 while $n++ < 8 && (
      # Flag then a separate operand: `env -S <op>` / `--split-string[=] <op>`,
      # and `bash|sh|dash|zsh|ksh -c <op>`.
      s{
        (?: \benv\b[^"\x27|;&\n]*?(?:-S|--split-string)(?:=|\s+)?
          | \b(?:bash|sh|dash|zsh|ksh)\b[^"\x27|;&\n]*?-[a-zA-Z]*c(?:\s+)
        )
        ("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27|\S+)
      }{ dq($1) }gex
      # A single QUOTED token that bundles the split-string flag WITH its value —
      # `env '"'"'--split-string=git …'"'"'` / `env "-Sgit …"` (PR #11 R6).
      || s{
        \benv\b[^|;&\n]*?
        ( "(?:--split-string=|-S)(?:[^"\\]|\\.)*" | \x27(?:--split-string=|-S)[^\x27]*\x27 )
      }{
        my $t = dq($1); $t =~ s/^(?:--split-string=|-S)//; $t;
      }gex
      # `git -c alias.NAME=VALUE NAME …` runs VALUE as the subcommand — expand it
      # so the guarded verb (commit/push/…) is visible, not hidden behind the
      # alias name (PR #11 R7).
      || s{
        \bgit\s+-c\s+alias\.([A-Za-z][\w-]*)=("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27|\S+)\s+\1(?=\s|$)
      }{ "git " . dq($2) }gex
    );
  ' 2>/dev/null
}
COMMAND_EXEC=$(printf '%s' "$COMMAND" | _flatten_exec)
[ -n "$COMMAND_EXEC" ] || COMMAND_EXEC="$COMMAND"

# COMMAND_NOSTR is COMMAND_EXEC with quoted strings NORMALIZED: a quoted string
# that is a single safe word is replaced by its bare content — the shell hands
# `git commit "--no-verify"` (and `"git" push`) to the OS as plain tokens, so
# guards must still see them (PR #11 review P1/R4). Anything else (spaces,
# separators, expansions) is blanked to "", so a commit message or echo argument
# that merely CONTAINS a flag literal can never trip a guard (audit A9). Partial
# quoting concatenates (`--no-ver"ify"` → `--no-verify`, `g"it"` → `git`),
# matching shell word-joining. ANSI-C (`$'…'`) and locale (`$"…"`) quoting also
# produce plain argv tokens (`git commit $'--no-verify'`; PR #11 R6) — the `$`
# prefix is consumed and ANSI-C/double content is backslash-processed. Leftmost-
# first alternation mirrors shell scanning.
COMMAND_NOSTR=$(printf '%s' "$COMMAND_EXEC" | perl -0777 -pe '
  s{
      \$\x27((?:[^\x27\\]|\\.)*)\x27     # $1: ANSI-C  $'"'"'...'"'"'
    | \$?"((?:[^"\\]|\\.)*)"             # $2: "..." or locale $"..."
    | \x27([^\x27]*)\x27                 # $3: plain  '"'"'...'"'"'
  }{
    my ($a,$d,$s) = ($1,$2,$3);
    my $c;
    if    (defined $a) { $c = $a; $c =~ s/\\(.)/$1/g; }
    elsif (defined $d) { $c = $d; $c =~ s/\\(.)/$1/g; }
    else               { $c = $s; }
    $c =~ m{^[A-Za-z0-9_+.,:\/=\@^~*-]+$} ? $c : q("")
  }gex' 2>/dev/null)

# _git_segments emits one line per simple command that IS a git/gh invocation,
# as `EFFDIR<TAB>SEGMENT`. EFFDIR is the directory the command actually operates
# on — `git -C <path> …` runs in <path>, so a hook resolving branch/registration
# in its own cwd would guard the WRONG checkout (PR #11 R4); stateful guards use
# EFFDIR. The raw command is split on separators — opening AND closing group
# delimiters (`(git reset …)` must not glue `)` to the last token; PR #11 R2) —
# OUTSIDE quotes; each segment is stripped of leading env assignments (VAR=1 git)
# and wrappers INCLUDING their options (`env -u NAME`, `sudo -u root`, `xargs`;
# PR #11 R2), path-qualified/alias forms are normalized (`/usr/bin/git`, `\git`;
# PR #11 R3), and git/gh global options before the subcommand (-C dir, -c k=v,
# --no-pager, -R owner/repo) are dropped so `git -C x push` reads as `git push`.
_git_segments() {
  printf '%s' "$COMMAND_NOSTR" | perl -0777 -ne '
    # resolve a (possibly relative) path against the running cwd
    sub _join { my ($base,$p) = @_; return $p if $p =~ m{^/}; return $p if $base eq "."; return "$base/$p"; }
    my $cwd = ".";   # tracks `cd <dir>` across `&&`/`;` segments (PR #11 R7)
    for my $seg (split /\|\||&&|[;|&\n()]|\$\(|`|\{[[:space:]]/) {
      $seg =~ s/^\s+//;
      # A leading `cd <dir>` moves the shell for the commands that follow, so a
      # later bare `git commit`/`push` runs THERE, not in the hook cwd (PR #11 R7).
      if ($seg =~ /^cd\s+(?:--\s+)?("[^"]*"|\x27[^\x27]*\x27|\S+)/) {
        my $t = $1; $t =~ s/^["\x27]//; $t =~ s/["\x27]$//;
        $cwd = _join($cwd, $t) if $t ne "" && $t ne "-";
        next;
      }
      next if $seg =~ /^cd(\s|$)/;   # `cd` home, or a blanked spaced arg
      my $again = 1;
      while ($again) {
        $again = 0;
        # Leading shell control keywords (`if git …; then`, `while gh …; do`)
        # still execute the command that follows (PR #11 R5).
        $again = 1 if $seg =~ s/^(?:if|then|elif|else|while|until|do|!)\s+//;
        $again = 1 if $seg =~ s/^[A-Za-z_][A-Za-z0-9_]*=\S*\s+//;
        $again = 1 if $seg =~ s/^(?:command|builtin|nohup|time)\s+(?:-\S+\s+)*//;
        $again = 1 if $seg =~ s/^sudo\s+(?:-[ugUTRDChp]\s+\S+\s+|-\S+\s+)*//;
        $again = 1 if $seg =~ s/^env\s+(?:(?:-[uCS]|--unset|--chdir)\s+\S+\s+|-\S+\s+|[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*//;
        $again = 1 if $seg =~ s/^xargs\s+(?:-[IiEeLlnPsda]\s+\S+\s+|-\S+\s+)*//;
      }
      $seg =~ s/^\\+//;
      $seg =~ s{^\S*/(git|gh)(?=\s|$)}{$1};
      next unless $seg =~ /^(?:git|gh)(?:\s|$)/;
      my $dir = $cwd;   # default to the cd-tracked cwd; -C overrides it
      $again = 1;
      while ($again) {
        $again = 0;
        # Alternate-context global options set the effective checkout (PR #11
        # R4/R5): -C <path> is a directory; --work-tree <path> is the tree;
        # --git-dir <path> is the .git, whose parent is the checkout. A relative
        # target resolves against the cd-tracked cwd. (-c is config key=value,
        # NOT a directory — case-sensitive.)
        if ($seg =~ s/^(git|gh)\s+-C(?:=|\s+)(\S+)\s+/$1 /)            { $dir = _join($cwd, $2); $again = 1; next; }
        if ($seg =~ s/^(git|gh)\s+--work-tree(?:=|\s+)(\S+)\s+/$1 /)   { $dir = _join($cwd, $2); $again = 1; next; }
        if ($seg =~ s/^(git|gh)\s+--git-dir(?:=|\s+)(\S+)\s+/$1 /)     { my $g = $2; $g =~ s{/\.git/?$}{}; $dir = ($g eq "" ? "/" : _join($cwd, $g)); $again = 1; next; }
        $again = 1 if $seg =~ s/^(git|gh)\s+(?:-c\s+\S+|-R\s+\S+|--(?:repo|namespace|exec-path)(?:=\S+|\s+\S+)?|--no-pager|--paginate|--bare|--literal-pathspecs)\s+/$1 /;
      }
      print "$dir\t$seg\n";
    }' 2>/dev/null
}

# --- Fast-path optimization ---
# Most Bash commands (ls, cat, grep, npm, node) don't need git-safety checks.
# NEEDS_GIT_CHECK is true only when a REAL git/gh command segment exists (a git
# literal inside quotes no longer counts). NEEDS_FILE_CHECK is true for redirects
# AND for the non-redirect writers block-file-redirect.sh inspects (audit A7).
# BOTH pre-greps run on COMMAND_NOSTR, not raw $COMMAND — a quoted command word
# (`"git" push`, `"cp" x y`) is a real invocation the shell executes, and only
# normalization reveals it (PR #11 R4).

NEEDS_GIT_CHECK=false
NEEDS_FILE_CHECK=false
GIT_SEGMENTS_D=""   # EFFDIR<TAB>SEGMENT lines (stateful guards)
GIT_SEGMENTS=""     # pure SEGMENT lines (stateless guards — unchanged interface)

if [ -n "$COMMAND_NOSTR" ]; then
  # Cheap pre-grep before spawning perl for segmentation.
  if echo "$COMMAND_NOSTR" | grep -qE '(^|[^[:alnum:]_.-])(git|gh)([[:space:]]|$)'; then
    GIT_SEGMENTS_D=$(_git_segments)
    # Drop the EFFDIR column for the stateless guards (cut is tab-aware; BSD sed
    # is not, and a real -C path contains letters that a `\t` bracket mismatches).
    GIT_SEGMENTS=$(printf '%s' "$GIT_SEGMENTS_D" | cut -f2-)
    [ -n "$GIT_SEGMENTS" ] && NEEDS_GIT_CHECK=true
  fi
  # Redirect detection: `>`/`>>`/`>|` followed by an eventual filename, WITH or
  # WITHOUT a space (`>foo` and `> foo` both redirect). Exclude fd-dup forms
  # (`>&`, `2>&1`) — the next char after `>` there is `&`, not a file. Also flag
  # the non-redirect writers (sed -i, cp, mv, dd, sponge — audit A7). This is
  # only a fast-path gate; block-file-redirect.sh does the precise check.
  if echo "$COMMAND_NOSTR" | grep -qE '(>[>|]?[[:space:]]*[^&|>[:space:]]|\btee\b|(^|[^[:alnum:]_.-])(sed|cp|mv|dd|sponge)([[:space:]]|$))'; then
    NEEDS_FILE_CHECK=true
  fi
fi

# Is the letsbuild multi-agent workflow ACTIVE in this repo? The worktree-discipline
# hooks (enforce-worktree, check-work-registration, check-branch-prefix, block-file-redirect)
# are deployed GLOBALLY but must only enforce where the workflow is set up — signalled by a
# registered row in .claude/active-work.md (a `| wX | … |` / `| xN | … |` / `| s | … |`
# line). Repos without registered work (the platform repo, one-off checkouts) → no-op.
# Only the worktree hooks call this; universal git guards ignore it and run everywhere.
# _resolve_dir <candidate>: echo it if it is a real git worktree, else `.`
# (the hook cwd). A `cd`/-C target that doesn't resolve — bogus, nonexistent, or
# not a repo — must NOT disable the guard (fail toward the current repo; PR #11 R7).
_resolve_dir() {
  local d="${1:-.}"
  if [ "$d" != "." ] && git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    printf '%s' "$d"
  else
    printf '.'
  fi
}

# _seg_effdir <subcommand>: the effective directory (`git -C <path>`) of the
# first git segment whose subcommand matches, else `.`. Lets the stateful commit
# guards resolve branch/registration at the checkout the command targets (R4).
_seg_effdir() {
  awk -F'\t' -v re="^git[[:space:]]+$1([[:space:]]|\$)" '$2 ~ re {print $1; exit}' <<< "$GIT_SEGMENTS_D"
}

# Both helpers accept an optional directory (default cwd) so a `git -C <path> …`
# command is evaluated against <path>, the checkout it actually writes (PR #11 R4).
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

# Fleet-SHAPED repo: a .claude/ directory exists in the worktree or main checkout.
# block-protected-branch gates on THIS, not on _fleet_active — deploy-branch
# protection must fail CLOSED (audit A8: an emptied/corrupted active-work.md made
# every fleet guard no-op, allowing a direct push to master). Worktree-discipline
# hooks still gate on _fleet_active, because registration is what signals that the
# letsbuild workflow is actually running.
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
