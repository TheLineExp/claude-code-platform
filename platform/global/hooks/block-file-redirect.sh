#!/bin/bash
# Block Bash commands that write to files in the main repo. Catches redirects
# (echo > file, cat >> file, >| file, tee) AND the non-redirect writers that
# bypassed them (audit A7): sed -i, cp/mv into the repo, dd of=, sponge. All
# targets come from the ONE tokenizer's argv model (_tokenize.pl), so this
# surface can no longer DRIFT from the git-side parser (the whole point of the
# 2026-07-05 rewrite — the grammar fuzzer's 6 leaks all lived on the old,
# separately-maintained writer lexer).
#
# Known residual: arbitrary interpreters (python -c "open('w')", perl -e, …) can
# still write files — unparseable from the command line; the real fix is
# filesystem-layer enforcement.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# Fast path: no redirect and no writer command detected.
$NEEDS_FILE_CHECK || exit 0

# Closes the enforce-worktree bypass, so it only applies where the letsbuild
# workflow is active. Elsewhere, Bash writes to repo files are fine.
_fleet_active || exit 0

# Only enforce in the main repo (not in worktrees).
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
if echo "$GIT_DIR" | grep -q "/worktrees/"; then exit 0; fi
if [ -f "$GIT_DIR" ] 2>/dev/null; then exit 0; fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

# Does a write target land INSIDE the repo tree? Covers relative paths (with or
# without a leading `./`) and absolute paths under $REPO_ROOT. Allows /dev/*,
# .claude/ setup files, ~/… and $VAR targets, and paths that escape via `..`.
under_repo() {
  local t="${1%\"}"; t="${t#\"}"; t="${t%\'}"; t="${t#\'}"   # defensive quote strip
  case "$t" in
    /dev/*)               return 1 ;;
    .claude/*|*/.claude/*) return 1 ;;
    '~'*|'$'*)            return 1 ;;
    ../*|*/../*)          return 1 ;;
    /*)
      [ -n "$REPO_ROOT" ] || return 1
      case "$t/" in "$REPO_ROOT/"*) return 0 ;; *) return 1 ;; esac ;;
    *)                   return 0 ;;
  esac
}

block_write() {
  echo "BLOCKED: Bash write to a repo file ('$1') detected in the main repo." >&2
  echo "Code modifications must happen in a worktree. Run /letsbuild first." >&2
  echo "(Writing to /tmp, /dev, ~/… or a path outside the repo is fine.)" >&2
  exit 2
}

# Per command: every write target is an argv token or a redirect target the
# tokenizer already resolved (quotes/wrappers stripped, `git -C`-style context
# irrelevant here). Emit and test each:
#   redirects        → CMD_REDIRS
#   cp/mv            → -t/--target-directory dest, else the last positional
#   sed (with -i)    → existing file operands (skip -e/-f script operands)
#   dd               → of= value
#   sponge           → its last file arg
#   tee              → each file arg
_wr_check() {
  local a cmd n i skip rest tdir dst
  local -a nonflag

  for a in "${CMD_REDIRS[@]}"; do
    [ -n "$a" ] || continue
    under_repo "$a" && block_write "$a"
  done

  cmd="${CMD_ARGV[0]}"; n=${#CMD_ARGV[@]}
  case "$cmd" in
    cp|mv)
      tdir=""; nonflag=(); i=1
      while [ $i -lt $n ]; do
        a="${CMD_ARGV[$i]}"
        case "$a" in
          --target-directory) i=$((i+1)); tdir="${CMD_ARGV[$i]}" ;;
          --target-directory=*) tdir="${a#--target-directory=}" ;;
          --*) : ;;
          -*t*) rest="${a##*t}"; if [ -n "$rest" ]; then tdir="$rest"; else i=$((i+1)); tdir="${CMD_ARGV[$i]}"; fi ;;
          -*) : ;;
          *) nonflag+=("$a") ;;
        esac
        i=$((i+1))
      done
      if [ -n "$tdir" ]; then
        under_repo "$tdir" && block_write "$tdir"
      elif [ ${#nonflag[@]} -ge 2 ]; then
        dst="${nonflag[$((${#nonflag[@]}-1))]}"
        under_repo "$dst" && block_write "$dst"
      fi ;;
    sed)
      skip=0
      for a in "${CMD_ARGV[@]:1}"; do case "$a" in -i*|--in-place*) skip=1 ;; esac; done
      [ $skip = 1 ] || return
      skip=0; i=1
      while [ $i -lt $n ]; do
        a="${CMD_ARGV[$i]}"
        if [ $skip = 1 ]; then skip=0; i=$((i+1)); continue; fi
        case "$a" in
          -e|-f|--expression|--file) skip=1 ;;
          -*) : ;;
          # sed file args are indistinguishable from scripts (`s/a/b/`) by shape;
          # require the token to be an existing file before treating it as a write.
          *) [ -f "$a" ] && { under_repo "$a" && block_write "$a"; } ;;
        esac
        i=$((i+1))
      done ;;
    dd)
      for a in "${CMD_ARGV[@]:1}"; do case "$a" in of=*) dst="${a#of=}"; under_repo "$dst" && block_write "$dst" ;; esac; done ;;
    sponge)
      nonflag=()
      for a in "${CMD_ARGV[@]:1}"; do case "$a" in -*) : ;; *) nonflag+=("$a") ;; esac; done
      [ ${#nonflag[@]} -ge 1 ] && { dst="${nonflag[$((${#nonflag[@]}-1))]}"; under_repo "$dst" && block_write "$dst"; } ;;
    tee)
      for a in "${CMD_ARGV[@]:1}"; do case "$a" in -*) : ;; *) under_repo "$a" && block_write "$a" ;; esac; done ;;
  esac
}

_for_each_command _wr_check
exit 0
