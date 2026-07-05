#!/bin/bash
# Block Bash commands that write to files in the main repo.
# Catches redirects (echo > file, cat >> file, >| file, tee file) AND the
# non-redirect writers that bypassed them (audit A7): sed -i, cp/mv into the
# repo, dd of=, sponge. This closes the bypass gap where enforce-worktree only
# catches Edit/Write tools.
#
# Known residual: arbitrary interpreters (python -c "open('w')", perl -e, …)
# can still write files — that is unparseable from the command line; the real
# fix for that class is filesystem-layer enforcement, not more regex.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no redirect operators and no writer commands detected
$NEEDS_FILE_CHECK || exit 0

# Global deployment: this closes the enforce-worktree bypass, so it only applies where
# the letsbuild workflow is active. Elsewhere, Bash writes to repo files are fine.
_fleet_active || exit 0

# Only enforce in the main repo (not in worktrees)
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
if echo "$GIT_DIR" | grep -q "/worktrees/"; then
  exit 0  # In a worktree, allow
fi

# Also allow if git-dir is just a file (worktree pointer)
if [ -f "$GIT_DIR" ] 2>/dev/null; then
  exit 0  # Worktree detected via .git file
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

# Does a write target land INSIDE the repo tree? Covers relative paths (with or
# without a leading `./`) and absolute paths under $REPO_ROOT. Explicitly allows
# /dev/*, .claude/ setup files, ~/… and $VAR targets, and paths that escape via `..`.
under_repo() {
  local t="${1%\"}"; t="${t#\"}"; t="${t%\'}"; t="${t#\'}"   # strip surrounding quotes
  case "$t" in
    /dev/*)               return 1 ;;   # device — allow
    .claude/*|*/.claude/*) return 1 ;;  # setup files — allow
    '~'*|'$'*)            return 1 ;;    # home/var expansion — not a repo-relative literal
    ../*|*/../*)          return 1 ;;    # escapes cwd — conservatively allow
    /*)                                  # absolute — block only if under the repo root
      [ -n "$REPO_ROOT" ] || return 1
      case "$t/" in "$REPO_ROOT/"*) return 0 ;; *) return 1 ;; esac ;;
    *)                   return 0 ;;     # plain relative → inside the repo
  esac
}

block_write() {
  echo "BLOCKED: Bash write to a repo file ('$1') detected in the main repo." >&2
  echo "Code modifications must happen in a worktree. Run /letsbuild first." >&2
  echo "(Writing to /tmp, /dev, ~/… or a path outside the repo is fine.)" >&2
  exit 2
}

# Extract every redirect/tee target. Redirects: `>`/`>>`/`>|` with or WITHOUT a
# space (`>f` and `> f`), excluding fd-dup forms (`>&`, `2>&1` — the char after
# `>` is `&`). tee: allow flags (`-a`, `--append`, …) before the filename.
# Operate on COMMAND_EXEC (env -S flattened; PR #11 R4) so a writer smuggled
# through `env -S "cp …"` is analyzed as the command it executes.
TARGETS=$(
  # unquoted targets (stop at whitespace)
  echo "$COMMAND_EXEC" | grep -oE '>[>|]?[[:space:]]*[^[:space:]|&;<>"'"'"']+' | sed -E 's/^>[>|]?[[:space:]]*//'
  echo "$COMMAND_EXEC" | grep -oE '\btee([[:space:]]+-{1,2}[a-zA-Z-]+)*[[:space:]]+[^[:space:]|&;<>"'"'"']+' | sed -E 's/^tee([[:space:]]+-{1,2}[a-zA-Z-]+)*[[:space:]]+//'
  # quoted targets — REQUIRED for paths with spaces (the repo dir "Volo Technologies")
  echo "$COMMAND_EXEC" | grep -oE '>[>|]?[[:space:]]*"[^"]+"' | sed -E 's/^>[>|]?[[:space:]]*//'
  echo "$COMMAND_EXEC" | grep -oE ">[>|]?[[:space:]]*'[^']+'" | sed -E "s/^>[>|]?[[:space:]]*//"
  echo "$COMMAND_EXEC" | grep -oE '\btee([[:space:]]+-{1,2}[a-zA-Z-]+)*[[:space:]]+"[^"]+"' | sed -E 's/^tee([[:space:]]+-{1,2}[a-zA-Z-]+)*[[:space:]]+//'
)

while IFS= read -r target; do
  [ -n "$target" ] || continue
  under_repo "$target" && block_write "$target"
done <<< "$TARGETS"

# Non-redirect writers (audit A7). A quote-aware lexer (so `cp x "src/my f.ts"`
# keeps its spaced target) splits the command into segments/tokens, strips env
# assignments and wrappers, and emits candidate write targets:
#   sed  → file args, only when -i/--in-place is present
#   cp/mv → the LAST path arg (the destination)
#   dd   → the of= value;  sponge → its file arg
WRITER_TARGETS=$(HOOK_CMD="$COMMAND_EXEC" perl -e '
  my $c = $ENV{HOOK_CMD} // "";
  my @segs; my @cur = ("");
  while (length $c) {
    if ($c =~ s/^[[:space:]]+//) { push @cur, "" if $cur[-1] ne ""; next; }
    if ($c =~ s/^(?:\|\||&&|[;|&\n()]|\$\(|`)//) { push @segs, [@cur]; @cur = (""); next; }
    if ($c =~ s/^\x27([^\x27]*)\x27//) { $cur[-1] .= $1; next; }
    if ($c =~ s/^"((?:[^"\\]|\\.)*)"//) { my $t = $1; $t =~ s/\\(.)/$1/g; $cur[-1] .= $t; next; }
    if ($c =~ s/^([^[:space:];|&()\x27"`]+)//) { $cur[-1] .= $1; next; }
    $c =~ s/^.//;
  }
  push @segs, [@cur];
  for my $seg (@segs) {
    my @t = grep { $_ ne "" } @$seg;
    # Wrapper stripping MUST consume wrapper OPTIONS too (`env -i cp …`,
    # `sudo -u root mv …` still run the writer — PR #11 R3). Keep this in
    # lockstep with _parse-input.sh::_git_segments; the bypass suite carries
    # paired cases for both surfaces.
    while (@t) {
      if ($t[0] =~ /^[A-Za-z_][A-Za-z0-9_]*=/) { shift @t; next; }
      if ($t[0] =~ /^(?:command|builtin|nohup|time)$/) {
        shift @t; shift @t while @t and $t[0] =~ /^-/; next;
      }
      if ($t[0] eq "sudo") {
        shift @t;
        while (@t and $t[0] =~ /^-/) { my $f = shift @t; shift @t if @t and $f =~ /^-[ugUTRDChp]$/; }
        next;
      }
      if ($t[0] eq "env") {
        shift @t;
        while (@t and ($t[0] =~ /^-/ or $t[0] =~ /^[A-Za-z_][A-Za-z0-9_]*=/)) {
          my $f = shift @t; shift @t if @t and ($f =~ /^-[uCS]$/ or $f eq "--unset" or $f eq "--chdir");
        }
        next;
      }
      if ($t[0] eq "xargs") {
        shift @t;
        while (@t and $t[0] =~ /^-/) { my $f = shift @t; shift @t if @t and $f =~ /^-[IiEeLlnPsda]$/; }
        next;
      }
      last;
    }
    next unless @t;
    my $cmd = shift @t; $cmd =~ s{.*/}{}; $cmd =~ s/^\\+//;
    if ($cmd eq "sed") {
      next unless grep { /^-i/ or /^--in-place/ } @t;
      for my $a (@t) { print "sed\t$a\n" unless $a =~ /^-/; }
    } elsif ($cmd eq "cp" or $cmd eq "mv") {
      # GNU -t/--target-directory names the DESTINATION explicitly (PR #11
      # review P2); when present, the positional args are all sources.
      my $tdir;
      for (my $i = 0; $i <= $#t; $i++) {
        my $a = $t[$i];
        if ($a =~ /^-[a-zA-Z]*t$/ or $a eq "--target-directory") { $tdir = $t[$i+1] if $i < $#t; }
        elsif ($a =~ /^--target-directory=(.*)$/) { $tdir = $1; }
        elsif ($a =~ /^-t(.+)$/) { $tdir = $1; }
      }
      if (defined $tdir and $tdir ne "") { print "dst\t$tdir\n"; }
      else { my @f = grep { !/^-/ } @t; print "dst\t$f[-1]\n" if @f >= 2; }
    } elsif ($cmd eq "dd") {
      for my $a (@t) { print "dst\t$1\n" if $a =~ /^of=(.+)$/; }
    } elsif ($cmd eq "sponge") {
      my @f = grep { !/^-/ } @t;
      print "dst\t$f[-1]\n" if @f;
    }
  }
' 2>/dev/null)

while IFS=$'\t' read -r kind target; do
  [ -n "$target" ] || continue
  # sed file args are indistinguishable from scripts (`s/a/b/`) by shape alone —
  # require the token to be an existing file before treating it as a write target.
  if [ "$kind" = "sed" ] && [ ! -f "$target" ]; then continue; fi
  under_repo "$target" && block_write "$target"
done <<< "$WRITER_TARGETS"

exit 0
