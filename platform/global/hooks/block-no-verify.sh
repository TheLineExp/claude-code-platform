#!/bin/bash
# Block --no-verify on git commands. Hooks must always run.
# Exit 2 = block, Exit 0 = allow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_parse-input.sh"

# --no-verify only means something on a git command. Matching walks ARGV TOKENS,
# so a commit message that merely MENTIONS --no-verify (audit A9, bit twice) is a
# single argv token this guard skips as the operand of -m.
$NEEDS_GIT_CHECK || exit 0

_nv_block() {
  echo "BLOCKED: --no-verify (or 'git commit -n') is not allowed. All hooks must run." >&2
  echo "If a hook is failing, fix the underlying issue instead of bypassing it." >&2
  exit 2
}

# Per command: does a git-commit carry a REAL no-verify flag? Walks tokens the
# way git's parser does (PR #11 R2 — `git commit -m "-n"` is a MESSAGE):
#   - operands of value-taking options (-m/-F/-C/-c/-t + long forms) are skipped
#   - `--` ends option parsing
#   - long form incl. the unambiguous prefixes git accepts (--no-veri, --no-verif)
#   - in a short cluster, a char after a value-taking letter is that option's
#     VALUE (`-mn` = message "n"), while n BEFORE one is --no-verify (`-nm x`)
_nv_check() {
  [ "${CMD_ARGV[0]}" = git ] || return
  local sub="${CMD_ARGV[1]}" n=${#CMD_ARGV[@]} i tok cluster j ch skip=0
  if [ "$sub" = commit ]; then
    i=2
    while [ $i -lt $n ]; do
      tok="${CMD_ARGV[$i]}"
      if [ "$skip" = 1 ]; then skip=0; i=$((i+1)); continue; fi
      case "$tok" in
        --) break ;;
        --no-veri|--no-verif|--no-verify) _nv_block ;;
        -m|-F|-C|-c|-t|--message|--file|--author|--date|--template|--fixup|--squash|--reuse-message|--reedit-message|--trailer|--cleanup|--pathspec-from-file)
          skip=1 ;;
        # --gpg-sign/-S take an OPTIONAL ATTACHED arg only, so a bare one never
        # eats the next token (PR #11 R3 — `--gpg-sign --no-verify` still blocks).
        --*) : ;;
        -?*)
          cluster="${tok#-}"; j=0
          while [ $j -lt ${#cluster} ]; do
            ch="${cluster:$j:1}"
            case "$ch" in
              n) _nv_block ;;
              S) break ;;
              m|F|C|c|t) [ $((j+1)) -ge ${#cluster} ] && skip=1; break ;;
            esac
            j=$((j+1))
          done ;;
      esac
      i=$((i+1))
    done
  else
    # push/merge/other: --no-verify (prefixes) but NO -n scan (`git push -n` is
    # --dry-run; `git merge -n` is --no-stat).
    for tok in "${CMD_ARGV[@]:2}"; do
      case "$tok" in --no-veri|--no-verif|--no-verify) _nv_block ;; esac
    done
  fi
}

_for_each_command _nv_check
exit 0
