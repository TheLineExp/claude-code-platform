#!/bin/bash
# hook-grammar-fuzz.sh — GRAMMAR-DRIVEN adversarial generator for the guard hooks.
#
# The curated hook-bypass-suite.sh only tests cases someone already thought of —
# which is why 7 rounds of Codex review kept finding new ones. This generator
# instead enumerates the SHELL GRAMMAR: for each dangerous operation it crosses
# every way the shell can obfuscate the command word, the flags/refspec, and the
# effective directory, and asserts the guard still fires. It is the process fix
# for "Codex finds these, our tests don't" — run it to find leaks FIRST.
#
# Output: per-family leak counts (should-block that ALLOWED) and false positives
# (should-allow that BLOCKED). Exit 0 iff zero leaks and zero false positives.
#
#   bash platform/tests/hook-grammar-fuzz.sh            # canonical hooks
#   HOOKS_DIR="$HOME/.claude/hooks" bash …             # live hooks

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="${HOOKS_DIR:-$REPO/platform/global/hooks}"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
GITC="git -c user.email=f@t -c user.name=f -c commit.gpgsign=false"

make_repo() { mkdir -p "$1"; git -C "$1" init -q -b "$2"; mkdir -p "$1/src";
  echo x > "$1/src/file.ts"; git -C "$1" add -A; $GITC -C "$1" commit -qm seed; }
register() { mkdir -p "$1/.claude"; { echo '| W | B | P | A | S |'; echo '|-|-|-|-|-|';
  echo '| w1 | feature/w1-x | ../wt | a | 2026-07-04 |'; } > "$1/.claude/active-work.md"; }

FEAT="$TMP/feat";   make_repo "$FEAT" "feature/w1-x"; register "$FEAT"
MASTER="$TMP/master"; make_repo "$MASTER" "master";   register "$MASTER"
# A protected checkout whose path CONTAINS A SPACE — the old regex parser could
# not carry a quoted spaced `-C`/`cd` target (documented residual (a)); the argv
# model emits it as one token, so these must now block.
MASTER_SP="$TMP/mas ter"; make_repo "$MASTER_SP" "master"; register "$MASTER_SP"

json_for() { CMD_STR="$1" perl -e 'my $c=$ENV{CMD_STR}; $c=~s/\\/\\\\/g; $c=~s/"/\\"/g;
  $c=~s/\n/\\n/g; print "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$c\"}}";'; }

# bash 3.2 (macOS) — no associative arrays; log every case, summarize at the end.
RESULTS="$TMP/results"; : > "$RESULTS"
run() { # $1 expect(block|allow) $2 hook $3 cwd $4 cmd $5 family
  local expect="$1" hook="$2" cwd="$3" cmd="$4" fam="$5" rc got status
  json_for "$cmd" | ( cd "$cwd" && bash "$HOOKS_DIR/$hook" ) >/dev/null 2>&1; rc=$?
  got=allow; [ "$rc" -eq 2 ] && got=block
  status=ok
  if [ "$got" != "$expect" ]; then
    if [ "$expect" = block ]; then status=leak; printf 'LEAK  [%-22s] %-8s %s\n' "$fam" "$hook" "$cmd"
    else status=fp; printf 'FALSE+[%-22s] %-8s %s\n' "$fam" "$hook" "$cmd"; fi
  fi
  printf '%s %s\n' "$fam" "$status" >> "$RESULTS"
}

# ---------------------------------------------------------------------------
# Dangerous cores: id | hook | command-word | rest-of-command
# Each MUST block when reached in a fleet repo.
# ---------------------------------------------------------------------------
# We build "$WORD $REST"; mutators rewrite $WORD (command-word family) or the
# whole string (wrapper family). REST is quote-free so it nests in bash -c "…".
CORES=(
  "protected|block-protected-branch.sh|git|push origin master"
  "noverify|block-no-verify.sh|git|commit --no-verify -m x"
  "force|block-destructive-git.sh|git|push --force origin feature/x"
  "reset|block-destructive-git.sh|git|reset --hard HEAD~1"
  "ghmerge|block-gh-merge.sh|gh|pr merge 5"
  "writer|block-file-redirect.sh|cp|/tmp/z src/file.ts"
)

# --- Wrapper grammar (F1: the command word is not at position 0) ---
# Templates use {C} for the full command. Non-nesting first, then nesting.
WRAPPERS_PLAIN=(
  '{C}'
  'VAR=1 {C}'
  'true; {C}'
  'true && {C}'
  'sudo {C}'
  'sudo -u root {C}'
  'env {C}'
  'env -i {C}'
  'env -u FOO {C}'
  'command {C}'
  'nohup {C}'
  'time {C}'
  'xargs {C}'
  'if {C}; then :; fi'
  'while {C}; do :; done'
  'until {C}; do :; done'
  '! {C}'
  '( {C} )'
  '{ {C}; }'
  'cd . && {C}'
)
WRAPPERS_NEST=(
  'bash -c "{C}"'
  'sh -c "{C}"'
  'env -S "{C}"'
  "env '--split-string={C}'"
)

# --- Command-word grammar (F1: how the word `git`/`gh`/`cp` is written) ---
mut_word() { # $1=word $2=variant  → echo mutated word
  local w="$1" v="$2" p
  case "$v" in
    id)    printf '%s' "$w" ;;
    dq)    printf '"%s"' "$w" ;;
    split) printf '%s"%s"' "${w:0:1}" "${w:1}" ;;
    mid)   local L=${#w}; printf '%s"%s"' "${w:0:L-1}" "${w:L-1}" ;;  # gi"t", g"h", c"p"
    wrap)  printf '""%s' "$w" ;;                                       # empty-quote prefix
    ansic) printf "\$'%s'" "$w" ;;
    bslash)printf '\\%s' "$w" ;;
    path)  case "$w" in cp) printf '/bin/cp' ;; *) printf '/usr/bin/%s' "$w" ;; esac ;;
  esac
}
WORD_VARIANTS=(id dq split mid wrap ansic bslash path)

# --- Flag grammar (F2) for --no-verify, and refspec grammar for protected ---
NOVERIFY_FORMS=('--no-verify' '"--no-verify"' "\$'--no-verify'" '--no-veri' '-n')
REFSPEC_FORMS=('origin master' 'origin HEAD:master' 'origin HEAD:refs/heads/master' 'origin +master' 'origin refs/heads/*')

emit() { local tpl="$1" c="$2"; printf '%s' "${tpl//\{C\}/$c}"; }

for core in "${CORES[@]}"; do
  IFS='|' read -r id hook word rest <<< "$core"

  # (1) WRAPPER sweep — command word = bare
  base="$word $rest"
  for tpl in "${WRAPPERS_PLAIN[@]}" "${WRAPPERS_NEST[@]}"; do
    run block "$hook" "$FEAT" "$(emit "$tpl" "$base")" "F1-wrapper"
  done

  # (2) COMMAND-WORD sweep — wrapper = none
  for v in "${WORD_VARIANTS[@]}"; do
    run block "$hook" "$FEAT" "$(mut_word "$word" "$v") $rest" "F1-cmdword"
  done

  # (3) WRAPPER × COMMAND-WORD sample (non-nesting wrappers only, quoted word)
  for tpl in 'sudo {C}' 'env -i {C}' 'if {C}; then :; fi' 'true; {C}'; do
    for v in dq ansic path; do
      run block "$hook" "$FEAT" "$(emit "$tpl" "$(mut_word "$word" "$v") $rest")" "F1-combo"
    done
  done
done

# (4) FLAG grammar (F2) — no-verify forms, each under a few wrappers
for form in "${NOVERIFY_FORMS[@]}"; do
  for tpl in '{C}' 'sudo {C}' 'bash -c "{C}"' 'if {C}; then :; fi' 'env -u X {C}'; do
    # bash -c nests double quotes — skip the dq no-verify form there
    case "$tpl" in 'bash -c "{C}"') case "$form" in '"--no-verify"') continue;; esac;; esac
    run block block-no-verify.sh "$FEAT" "$(emit "$tpl" "git commit $form -m x")" "F2-flag"
  done
done

# (5) REFSPEC grammar (F2) — protected push forms, each under a few wrappers
for form in "${REFSPEC_FORMS[@]}"; do
  for tpl in '{C}' 'sudo {C}' 'bash -c "{C}"' 'cd . && {C}'; do
    run block block-protected-branch.sh "$FEAT" "$(emit "$tpl" "git push $form")" "F2-refspec"
  done
done

# (6) EFFECTIVE-CONTEXT grammar (F3) — operate on the protected checkout
run block block-protected-branch.sh "$FEAT" "cd \"$MASTER\" && git commit -m x"       "F3-context"
run block block-protected-branch.sh "$FEAT" "cd \"$MASTER\"; git push"                "F3-context"
run block block-protected-branch.sh "$FEAT" "git -C \"$MASTER\" commit -m x"          "F3-context"
run block block-protected-branch.sh "$FEAT" "git -C \"$MASTER\" push"                 "F3-context"
run block block-protected-branch.sh "$FEAT" "git --git-dir=\"$MASTER/.git\" --work-tree=\"$MASTER\" commit -m x" "F3-context"
run block block-no-verify.sh        "$FEAT" "git -c alias.c='commit --no-verify' c -m x" "F3-context"

# (7) A9 INVERSE — dangerous literals that are DATA, not commands: must ALLOW
run allow block-no-verify.sh        "$FEAT" 'git commit -m "wip: skip --no-verify here"' "F4-falsepos"
run allow block-destructive-git.sh  "$FEAT" 'git commit -m "note: git push --force is banned"' "F4-falsepos"
run allow block-protected-branch.sh "$FEAT" 'echo "git push origin master"'            "F4-falsepos"
run allow block-destructive-git.sh  "$FEAT" 'grep -rn "git reset --hard" docs/'        "F4-falsepos"
run allow block-gh-merge.sh         "$FEAT" 'git commit -m "gh pr merge comes later"'  "F4-falsepos"
run allow block-protected-branch.sh "$FEAT" 'git push origin feature/staging-fix'      "F4-falsepos"
run allow block-file-redirect.sh    "$FEAT" 'cp src/file.ts /tmp/out.ts'               "F4-falsepos"

# (8) WRITER-TARGET grammar (F5) — every non-redirect writer AND redirect form,
# crossed with an in-repo destination (must BLOCK) vs an outside one (must
# ALLOW), under a few wrappers incl. one that re-lexes (`bash -c`). This is the
# surface where ALL SIX original leaks lived (the drifted second parser); it is
# now fed by the same tokenizer as the git guards. `sed`'s target must EXIST to
# count (a script `s/a/b/` is not a file), so the outside `/tmp/…` sed case is a
# genuine allow.
WR_WRAPS=('{C}' 'sudo {C}' 'bash -c "{C}"' '{ {C}; }')
wr() { # $1 command  $2 expect(block|allow)
  local raw="$1" expect="$2" tpl
  for tpl in "${WR_WRAPS[@]}"; do
    run "$expect" block-file-redirect.sh "$FEAT" "$(emit "$tpl" "$raw")" "F5-writer"
  done
}
IN='src/wtarget.ts'; OUT='/tmp/ff_out.ts'
for w in 'cp src/file.ts %D' 'mv src/file.ts %D' 'dd if=src/file.ts of=%D' \
         'tee %D' 'sponge %D' 'echo x > %D' 'echo x >> %D'; do
  wr "${w/\%D/$IN}"  block
  wr "${w/\%D/$OUT}" allow
done
# sed -i target must exist to be a write: src/file.ts (in-repo) blocks; a
# nonexistent outside path is not treated as a target.
wr 'sed -i s/a/b/ src/file.ts' block
wr "sed -i s/a/b/ $OUT"         allow
# cp -t <dir> destination form
wr 'cp -t src src/file.ts'  block
wr 'cp -t /tmp src/file.ts' allow

# (9) NESTED wrappers (F6) — a re-lexing wrapper around another wrapper. Each
# dangerous core must still block when buried two layers deep.
for core in "${CORES[@]}"; do
  IFS='|' read -r id hook word rest <<< "$core"
  base="$word $rest"
  run block "$hook" "$FEAT" "bash -c \"sudo $base\""     "F6-nested"
  run block "$hook" "$FEAT" "sudo bash -c \"$base\""     "F6-nested"
done

# (10) SPACED-CONTEXT grammar (F7) — a quoted alternate-context path containing a
# space. The old string parser lost the path after the space (residual (a)); the
# argv model keeps it as one token, so a commit/push aimed at the spaced-path
# MASTER checkout is judged by ITS branch and blocked.
run block block-protected-branch.sh "$FEAT" "git -C \"$MASTER_SP\" commit -m x"      "F7-spaced"
run block block-protected-branch.sh "$FEAT" "cd \"$MASTER_SP\" && git commit -m x"   "F7-spaced"
run block block-protected-branch.sh "$FEAT" "git -C \"$MASTER_SP\" push"             "F7-spaced"

# (11) FAKE-OPENER grammar (F8) — a `<<WORD` that is NOT a real heredoc opener
# because it is QUOTED or inside a COMMENT. It must never queue a phantom delimiter
# that swallows the real dangerous command on the following line. This class lived
# in NEITHER this fuzzer NOR the curated suite until the outside-reviewer found it
# (the regex pre-strip was quote/comment-blind); the tokenizer now handles heredocs
# with full quote/comment state, so every fake opener leaves the next line exposed.
FAKE_OPENERS=(
  'echo x # <<EOF'          # <<WORD in a comment
  'echo '\''<<EOF'\'''      # <<WORD single-quoted
  'echo "<<EOF"'            # <<WORD double-quoted
  'git log --grep "<<EOF"'  # <<WORD inside a quoted flag argument (non-adversarial)
)
for core in "${CORES[@]}"; do
  IFS='|' read -r id hook word rest <<< "$core"
  for opener in "${FAKE_OPENERS[@]}"; do
    run block "$hook" "$FEAT" "$opener"$'\n'"$word $rest" "F8-fakeopener"
  done
done
# INVERSE — a REAL heredoc body carrying the same literal must still ALLOW (data,
# not a command): guards against over-correcting the fix into a false-positive.
run allow block-destructive-git.sh  "$FEAT" $'git commit -F - <<EOF\ngit push --force origin x\nEOF' "F8-fakeopener"
run allow block-protected-branch.sh "$FEAT" $'git commit -F - <<EOF\ngit push origin master\nEOF'    "F8-fakeopener"

# ---------------------------------------------------------------------------
echo
echo "hooks: $HOOKS_DIR"
awk '
  { tot[$1]++; totN++ }
  $2=="leak" { leak[$1]++; totL++ }
  $2=="fp"   { fp[$1]++;   totF++ }
  END {
    order="F1-wrapper F1-cmdword F1-combo F2-flag F2-refspec F3-context F4-falsepos F5-writer F6-nested F7-spaced F8-fakeopener";
    n=split(order,f," ");
    printf "%-24s %7s %7s %7s\n","FAMILY","TOTAL","LEAKS","FALSE+";
    for(i=1;i<=n;i++){k=f[i]; printf "%-24s %7d %7d %7d\n",k,tot[k]+0,leak[k]+0,fp[k]+0}
    printf "%-24s %7d %7d %7d\n","TOTAL",totN+0,totL+0,totF+0;
    print (totL+totF==0) ? "CLEAN" : "LEAKS/FALSE+ PRESENT";
  }' "$RESULTS"
grep -qE ' (leak|fp)$' "$RESULTS" && exit 1 || exit 0
