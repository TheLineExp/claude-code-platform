#!/bin/bash
# hook-bypass-suite.sh — adversarial shell-input tests for the guard hooks.
#
# Feeds every verified bypass string from docs/AUDIT-2026-07-04-fable.md (Theme A)
# through each hook via its real stdin JSON protocol (see hooks/_parse-input.sh) and
# asserts the exit code — INCLUDING the A9 false-positive strings, which must be
# ALLOWED. Run this before AND after any hook edit; never judge a guard regex from
# a diff alone (that's how the audit's holes shipped).
#
# Usage:
#   bash platform/tests/hook-bypass-suite.sh                   # canonical repo hooks
#   HOOKS_DIR="$HOME/.claude/hooks" \
#   SETTINGS_FILE="$HOME/.claude/settings.json" \
#     bash platform/tests/hook-bypass-suite.sh                 # LIVE deployed hooks
#
# Exit 0 = all green; exit 1 = at least one case failed.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="${HOOKS_DIR:-$REPO/platform/global/hooks}"
SETTINGS_FILE="${SETTINGS_FILE:-$REPO/platform/global/claude-settings.template.json}"
SESSION_GUARD="${SESSION_GUARD:-$(dirname "$HOOKS_DIR")/session-guard.js}"
# Canonical layout keeps session-guard.js next to hooks/' parent; live layout keeps
# it inside ~/.claude/hooks' parent too — fall back to the canonical copy.
[ -f "$SESSION_GUARD" ] || SESSION_GUARD="$REPO/platform/global/session-guard.js"

PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

GITC="git -c user.email=suite@test -c user.name=suite -c commit.gpgsign=false"

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

make_repo() { # $1=dir $2=branch
  mkdir -p "$1"
  git -C "$1" init -q -b "$2"
  echo seed > "$1/seed.txt"
  mkdir -p "$1/src"
  echo 'export const x = 1' > "$1/src/file.ts"
  echo 'export const y = 2' > "$1/src/my file.ts"
  echo 's/a/b/' > "$1/src/edit.sed"
  git -C "$1" add -A
  $GITC -C "$1" commit -qm seed
}

register_work() { # $1=dir  — registered active-work row (fleet ACTIVE)
  mkdir -p "$1/.claude"
  {
    echo '| Window | Branch | Worktree Path | Area | Started |'
    echo '|--------|--------|---------------|------|---------|'
    echo '| w1 | feature/w1-x | ../wt | area | 2026-07-04 |'
  } > "$1/.claude/active-work.md"
}

empty_work() { # $1=dir — .claude exists but active-work.md has NO rows (A8 shape)
  mkdir -p "$1/.claude"
  {
    echo '| Window | Branch | Worktree Path | Area | Started |'
    echo '|--------|--------|---------------|------|---------|'
  } > "$1/.claude/active-work.md"
}

FLEET_FEAT="$TMP/fleet_feat"     # fleet-active, on a registered feature branch
FLEET_MASTER="$TMP/fleet_master" # fleet-active, standing on master
FLEET_EMPTY="$TMP/fleet_empty"   # .claude present, active-work.md EMPTIED (A8)
FLEET_UNREG="$TMP/fleet_unreg"   # fleet-active, on an UNregistered feature branch
PLAIN="$TMP/plain"               # personal repo, no .claude — guards must skip

make_repo "$FLEET_FEAT" "feature/w1-x";   register_work "$FLEET_FEAT"
make_repo "$FLEET_MASTER" "master";        register_work "$FLEET_MASTER"
make_repo "$FLEET_EMPTY" "master";         empty_work "$FLEET_EMPTY"
make_repo "$FLEET_UNREG" "feature/w2-y";   register_work "$FLEET_UNREG"
make_repo "$PLAIN" "main"

# Linked worktree of the fleet repo — worktree writes must be ALLOWED
FLEET_WT="$TMP/fleet_wt"
git -C "$FLEET_FEAT" worktree add -q "$FLEET_WT" -b feature/w1-wt

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

json_for() { # $1=command → PreToolUse Bash JSON on stdout
  CMD_STR="$1" perl -e '
    my $c = $ENV{CMD_STR};
    $c =~ s/\\/\\\\/g; $c =~ s/"/\\"/g; $c =~ s/\n/\\n/g; $c =~ s/\t/\\t/g;
    print "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$c\"}}";
  '
}

run_case() { # $1=expect(block|allow) $2=hook $3=cwd $4=command $5=label
  local expect="$1" hook="$2" cwd="$3" cmd="$4" label="$5" rc
  json_for "$cmd" | ( cd "$cwd" && bash "$HOOKS_DIR/$hook" ) >/dev/null 2>&1
  rc=$?
  local got="allow"
  [ "$rc" -eq 2 ] && got="block"
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then got="error($rc)"; fi
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS+1))
    printf 'ok   %-28s %-6s %s\n' "[$hook]" "$expect" "$label"
  else
    FAIL=$((FAIL+1))
    printf 'FAIL %-28s want=%s got=%s %s\n     cmd: %s\n' "[$hook]" "$expect" "$got" "$label" "$cmd"
  fi
}

block() { run_case block "$@"; }
allow() { run_case allow "$@"; }

# ---------------------------------------------------------------------------
# block-protected-branch.sh — A1 (prefix bypasses), A3 (refspec), A8 (fail-open)
# ---------------------------------------------------------------------------
H=block-protected-branch.sh
block "$H" "$FLEET_FEAT" 'git push origin master'                        'baseline: push refspec to master'
block "$H" "$FLEET_FEAT" 'cd wt && git push origin master'               'A1: cd prefix'
block "$H" "$FLEET_FEAT" 'VAR=1 git push origin master'                  'A1: env-assignment prefix'
block "$H" "$FLEET_FEAT" 'true; git push origin master'                  'A1: command-separator prefix'
block "$H" "$FLEET_FEAT" 'git -C . push origin master'                   'A1-class: git global opt before subcommand'
block "$H" "$FLEET_FEAT" 'echo $(git push origin master)'                'R2: inside command substitution'
block "$H" "$FLEET_FEAT" 'sudo -u root git push origin master'           'R2: sudo with options'
block "$H" "$FLEET_FEAT" 'echo x | xargs git push origin master'         'R2: xargs wrapper'
block "$H" "$FLEET_FEAT" '/usr/bin/git push origin master'               'R3: path-qualified git'
block "$H" "$FLEET_FEAT" '\git push origin master'                       'R3-class: backslash alias-bypass'
block "$H" "$FLEET_FEAT" '"git" push origin master'                      'R4: quoted command word'
block "$H" "$FLEET_FEAT" 'g"it" push origin master'                      'R4: split-quoted command word'
block "$H" "$FLEET_FEAT" 'env -S "git push origin master"'              'R4: env -S command string'
block "$H" "$FLEET_MASTER" 'git -C "'"$FLEET_MASTER"'" push'            'R4: -C into a protected checkout (push)'
block "$H" "$FLEET_FEAT"   'git -C "'"$FLEET_MASTER"'" commit -m "x"'   'R4: -C into a protected checkout (commit)'
block "$H" "$FLEET_FEAT"   'git -C "'"$FLEET_MASTER"'" push origin HEAD:staging' 'R4: -C + refspec to protected'
allow "$H" "$FLEET_FEAT"   'git -C "'"$FLEET_FEAT"'" commit -m "x"'     'R4: -C into a feature checkout is fine'
block "$H" "$FLEET_FEAT"   'git --git-dir="'"$FLEET_MASTER"'/.git" --work-tree="'"$FLEET_MASTER"'" commit -m "x"' 'R5: --git-dir/--work-tree into protected'
block "$H" "$FLEET_MASTER" 'if git commit -m "x"; then :; fi'          'R5: control keyword before commit'
block "$H" "$FLEET_FEAT"   'while git push origin master; do :; done'  'R5: control keyword before push'
block "$H" "$FLEET_FEAT"   'bash -c "git push origin master"'          'R5: bash -c payload'
block "$H" "$FLEET_FEAT"   'sh -c "git push origin HEAD:staging"'      'R5: sh -c payload'
block "$H" "$FLEET_FEAT"   'cd "'"$FLEET_MASTER"'" && git commit -m "x"' 'R7: cd into protected then commit'
block "$H" "$FLEET_FEAT"   'cd "'"$FLEET_MASTER"'"; git push'          'R7: cd into protected then push'
allow "$H" "$FLEET_FEAT"   'cd "'"$FLEET_FEAT"'" && git commit -m "x"' 'R7: cd into feature checkout is fine'
block "$H" "$FLEET_FEAT" 'git push origin HEAD:staging'                  'baseline: HEAD:staging'
block "$H" "$FLEET_FEAT" 'git push origin HEAD:refs/heads/staging'       'A3: fully-qualified refspec'
block "$H" "$FLEET_FEAT" 'git push origin refs/heads/master'             'A3: fully-qualified source-less'
block "$H" "$FLEET_FEAT" 'git push origin +master'                       'A3/A4: forced protected refspec'
block "$H" "$FLEET_FEAT" 'git push origin --delete staging'              'protected-branch remote delete'
allow "$H" "$FLEET_FEAT" 'git push origin feature/staging-fix'           'FP guard: branch NAMED staging-ish'
allow "$H" "$FLEET_FEAT" 'git push origin feature/w1-x'                  'normal feature push'
allow "$H" "$FLEET_FEAT" 'echo "git push origin master"'                 'A9-class: literal in echo'
allow "$H" "$FLEET_FEAT" 'git commit -m "true; git push origin master"'  'A9-class: literal in -m'
# HEREDOC class (A9 via heredoc): a commit whose -F - message body quotes a
# dangerous git command at LINE START must NOT trip a guard — the heredoc body is
# stdin data, stripped upstream in _parse-input.sh. But a REAL command AFTER the
# closing delimiter must still fire.
allow block-protected-branch.sh "$FLEET_FEAT" $'git commit -F - <<EOF\nnotes:\ngit push origin master\nEOF'          'heredoc: protected literal in body → allow'
allow block-no-verify.sh        "$FLEET_FEAT" $'git commit -F - <<EOF\nwhy:\ngit commit --no-verify\nEOF'            'heredoc: --no-verify in body → allow'
allow block-destructive-git.sh  "$FLEET_FEAT" $'git commit -F - <<EOF\nfix:\ngit push --force origin x\ngit reset --hard\nEOF' 'heredoc: force/reset in body → allow'
allow block-destructive-git.sh  "$FLEET_FEAT" $'git commit -F - <<-EOF\n\tgit push --force\n\tEOF'                   'heredoc: <<- indented delimiter → allow'
allow block-destructive-git.sh  "$FLEET_FEAT" $'git commit -F - <<\x27EOF\x27\ngit push --force origin x\nEOF'       'heredoc: quoted delimiter → allow'
block block-destructive-git.sh  "$FLEET_FEAT" $'git commit -F - <<EOF\nnote\nEOF\ngit push --force origin x'         'heredoc: REAL force push after close → block'
block block-protected-branch.sh "$FLEET_FEAT" $'git commit -F - <<EOF\nnote\nEOF\ngit push origin master'           'heredoc: REAL protected push after close → block'
# opener-line continuation (the false-NEGATIVE the single-regex strip introduced):
# a real command sharing the heredoc's OPENER line via a separator must survive.
block block-destructive-git.sh  "$FLEET_FEAT" $'git commit -F - <<EOF; git push --force origin x\nbody\nEOF'        'heredoc: REAL force after ; on opener → block'
block block-destructive-git.sh  "$FLEET_FEAT" $'git commit -F - <<EOF && git reset --hard\nbody\nEOF'               'heredoc: REAL reset after && on opener → block'
block block-destructive-git.sh  "$FLEET_FEAT" $'git commit -F - <<EOF | git clean -fdx\nbody\nEOF'                  'heredoc: REAL clean after | on opener → block'
block block-protected-branch.sh "$FLEET_FEAT" $'git commit -F - <<EOF & git push origin master\nbody\nEOF'          'heredoc: REAL protected push after & on opener → block'
allow block-destructive-git.sh  "$FLEET_FEAT" $'git commit -F - <<A <<B\nbodyA has git push --force\nA\nbodyB git reset --hard\nB' 'heredoc: multiple heredocs, both bodies dropped → allow'
# here-string `<<<WORD` must NOT be read as a heredoc (`<<` matching the 2nd-3rd `<`
# would queue a phantom delimiter and swallow the real command after it → bypass).
block block-destructive-git.sh  "$FLEET_FEAT" $'cat <<<EOF\ngit push --force origin main'                            'here-string <<<WORD: real force after → block'
block block-protected-branch.sh "$FLEET_FEAT" $'cat <<<WORD\ngit push origin master'                                'here-string <<<WORD: real protected push after → block'
block block-file-redirect.sh    "$FLEET_FEAT" $'cat <<<EOF\nsed -i s/a/b/ src/file.ts'                              'here-string <<<WORD: real writer after → block'
# CRLF: the close line arrives as `EOF\r`; without \r-stripping the body never ends
# and the real trailing command is dropped → bypass.
block block-destructive-git.sh  "$FLEET_FEAT" $'git commit -F - <<EOF\r\nm\r\nEOF\r\ngit push -f origin main'       'heredoc CRLF: real force after close → block'
allow block-destructive-git.sh  "$FLEET_FEAT" $'git commit -F - <<EOF\r\ngit push --force\r\nEOF\r'                 'heredoc CRLF: danger in body → allow'
# FAKE openers — a `<<WORD` that is QUOTED or in a COMMENT is NOT a heredoc, so it must
# not queue a phantom delimiter that swallows the real command after it (outside-review
# P1 on this branch: the regex pre-strip was quote/comment-blind; the tokenizer isn't).
block block-destructive-git.sh  "$FLEET_FEAT" $'echo hi # <<EOF\ngit push --force origin master'                    'fake heredoc in COMMENT: real force after → block'
block block-protected-branch.sh "$FLEET_FEAT" $'echo hi # <<EOF\ngit push origin master'                            'fake heredoc in COMMENT: real protected push after → block'
block block-destructive-git.sh  "$FLEET_FEAT" $'echo \x27<<EOF\x27\ngit push --force origin master'                 'fake heredoc SINGLE-quoted: real force after → block'
block block-destructive-git.sh  "$FLEET_FEAT" $'echo "<<EOF"\ngit push --force origin master'                       'fake heredoc DOUBLE-quoted: real force after → block'
block block-file-redirect.sh    "$FLEET_FEAT" $'echo \x27<<EOF\x27\nsed -i s/a/b/ src/file.ts'                      'fake heredoc SINGLE-quoted: real writer after → block'
block block-destructive-git.sh  "$FLEET_FEAT" $'git log --grep "fix <<HEAD bug"\ngit push --force origin master'    'non-adversarial <<WORD in quoted grep arg: real force after → block'
# FAKE openers via ARITHMETIC — `<<`/`>>` inside `$(( … ))` or `(( … ))` are C shift
# operators, not heredoc openers. bash rejects a real command inside arithmetic
# (`((echo hi))` is a syntax error), so a dangerous command AFTER the arithmetic must
# survive tokenizing (Codex P2: `echo $((1<<2))` was misread as a `1<<2` heredoc whose
# body swallowed the next line's real force-push).
block block-destructive-git.sh  "$FLEET_FEAT" $'echo $((1<<2))\ngit push --force origin main'      'arith-expansion $((1<<2)): real force after → block'
block block-protected-branch.sh "$FLEET_FEAT" $'echo $((1<<2))\ngit push origin master'            'arith-expansion $((1<<2)): real protected push after → block'
block block-destructive-git.sh  "$FLEET_FEAT" $'(( 1<<2 )); git push --force origin main'           'arith-command (( 1<<2 )): real force after → block'
block block-destructive-git.sh  "$FLEET_FEAT" $'echo $(( (1<<2) + 3 ))\ngit reset --hard'           'arith nested-paren $(( (x)+y )): real reset after → block'
block block-file-redirect.sh    "$FLEET_FEAT" $'echo $((2>>1))\nsed -i s/a/b/ src/file.ts'          'arith right-shift $((2>>1)): real writer after → block'
allow block-destructive-git.sh  "$FLEET_FEAT" 'echo $((1<<2)) done'                                  'arith-expansion alone: no dangerous cmd → allow'
# A command substitution INSIDE arithmetic still EXECUTES in bash — its inner command must be
# scanned, not dropped with the span (Codex P2: consuming the whole $(( … )) span swallowed it).
block block-destructive-git.sh  "$FLEET_FEAT" 'echo $(( $(git push --force origin main >/dev/null; echo 1) + 1 ))' 'cmdsub inside $(( )): real force → block'
block block-protected-branch.sh "$FLEET_FEAT" 'echo $(( $(git push origin master) + 0 ))'            'cmdsub inside $(( )): real protected push → block'
block block-destructive-git.sh  "$FLEET_FEAT" 'echo $(( `git push --force origin x` + 1 ))'          'backtick inside $(( )): real force → block'
allow block-destructive-git.sh  "$FLEET_FEAT" 'echo $(( $(date +%s) + 1 ))'                          'SAFE cmdsub inside $(( )): no danger → allow'
# DOUBLE-QUOTED command substitution — bash runs `$( … )`/backticks inside "…" (read_dq folded
# it into opaque word text → a pre-existing bypass surfaced via the arithmetic path; Codex P2).
block block-destructive-git.sh  "$FLEET_FEAT" 'echo "$(git push --force origin main)"'              'dq cmdsub: real force → block'
block block-destructive-git.sh  "$FLEET_FEAT" 'X="$(git push --force origin main)"'                 'dq cmdsub in assignment: real force → block'
block block-protected-branch.sh "$FLEET_FEAT" 'echo "wrap $(git push origin master) here"'          'dq cmdsub mid-string: real protected push → block'
block block-destructive-git.sh  "$FLEET_FEAT" 'echo "`git push --force origin x`"'                  'backtick inside dq: real force → block'
block block-file-redirect.sh    "$FLEET_FEAT" 'echo "$(sed -i s/a/b/ src/file.ts)"'                 'dq cmdsub: real writer → block'
allow block-destructive-git.sh  "$FLEET_FEAT" 'echo "$(date +%s) done"'                             'SAFE dq cmdsub: no danger → allow'
allow block-destructive-git.sh  "$FLEET_FEAT" $'echo \x27$(git push --force origin x)\x27'          'single-quoted sub: not executed → allow'
block "$H" "$FLEET_MASTER" 'git commit -m "x"'                           'commit while standing on master'
block "$H" "$FLEET_MASTER" 'git push'                                    'bare push while standing on master'
block "$H" "$FLEET_MASTER" 'git merge feature/w1-x'                      'merge while standing on master'
block "$H" "$FLEET_FEAT" 'git push origin "master"'                      'PR11-P1: quoted protected branch'
block "$H" "$FLEET_FEAT" 'git push origin "+master"'                     'PR11-P1: quoted forced protected refspec'
block "$H" "$FLEET_FEAT" 'git push origin "HEAD:staging"'                'PR11-P1: quoted refspec'
block "$H" "$FLEET_FEAT" 'git push origin "refs/heads/*"'                'glob refspec can write protected branches'
block "$H" "$FLEET_FEAT" 'git push origin refs/heads/*:refs/heads/*'     'glob matching-refspec'
block "$H" "$FLEET_EMPTY" 'git push origin master'                       'A8: EMPTIED active-work must fail CLOSED'
block "$H" "$FLEET_EMPTY" 'git commit -m "x"'                            'A8: commit on master, emptied active-work'
allow "$H" "$PLAIN" 'git commit -m "x"'                                  'personal repo (no .claude): trunk commits OK'
allow "$H" "$PLAIN" 'git push origin main'                               'personal repo (no .claude): push main OK'

# ---------------------------------------------------------------------------
# block-no-verify.sh — A2 (-n short form), A9 (false positives)
# ---------------------------------------------------------------------------
H=block-no-verify.sh
block "$H" "$FLEET_FEAT" 'git commit --no-verify -m "x"'                 'baseline: long flag'
block "$H" "$FLEET_FEAT" 'git commit -n -m "x"'                          'A2: short -n'
block "$H" "$FLEET_FEAT" 'git commit -anm "x"'                           'A2: bundled -anm'
block "$H" "$FLEET_FEAT" 'git commit --no-veri -m "x"'                   'A2-class: unambiguous long-opt prefix'
block "$H" "$FLEET_FEAT" 'git push --no-verify'                          'push --no-verify (pre-push hook skip)'
block "$H" "$FLEET_FEAT" 'cd wt && git commit -n -m "x"'                 'A1-class prefix + A2'
block "$H" "$FLEET_FEAT" 'git commit "--no-verify" -m "x"'               'PR11-P1: quoted flag token'
block "$H" "$FLEET_FEAT" 'git commit --no-ver"ify" -m "x"'               'PR11-P1: partial-quote concatenation'
block "$H" "$FLEET_FEAT" 'env -i git commit --no-verify -m "x"'          'R2: env with options'
block "$H" "$FLEET_FEAT" 'env -u GIT_DIR git commit -n -m "x"'           'R2: env -u NAME wrapper'
block "$H" "$FLEET_FEAT" '(git commit -n -m "x")'                        'R2: subshell parens'
block "$H" "$FLEET_FEAT" 'git commit -nm "x"'                            'R2-adjacent: n before m in cluster'
block "$H" "$FLEET_FEAT" '/opt/homebrew/bin/git commit --no-verify -m "x"' 'R3: path-qualified git'
block "$H" "$FLEET_FEAT" 'git commit --gpg-sign --no-verify -m "x"'      'R3: bare --gpg-sign must not eat the next flag'
block "$H" "$FLEET_FEAT" '"git" commit --no-verify -m "x"'              'R4: quoted command word'
block "$H" "$FLEET_FEAT" 'env -S "git commit --no-verify -m x"'         'R4: env -S command string'
block "$H" "$FLEET_FEAT" 'bash -c "git commit --no-verify -m x"'        'R5: bash -c payload'
block "$H" "$FLEET_FEAT" 'if git commit -n -m "x"; then :; fi'          'R5: control keyword before commit'
block "$H" "$FLEET_FEAT" 'git commit $'\''--no-verify'\'' -m "x"'        'R6: ANSI-C $'\''...'\'' quoted flag'
block "$H" "$FLEET_FEAT" 'env '\''--split-string=git commit --no-verify -m x'\''' 'R6: quoted --split-string= token'
block "$H" "$FLEET_FEAT" 'git -c alias.c='\''commit --no-verify'\'' c -m "x"' 'R7: -c alias hiding no-verify commit'
allow "$H" "$FLEET_FEAT" 'git commit -am "x"'                            'FP guard: -am has no n'
allow "$H" "$FLEET_FEAT" 'git commit -m "document --no-verify usage"'    'A9: flag literal inside -m'
allow "$H" "$FLEET_FEAT" 'grep -rn -- --no-verify hooks/'                'A9: flag literal in grep'
allow "$H" "$FLEET_FEAT" 'echo "--no-verify is banned"'                  'A9: flag literal in echo'
allow "$H" "$FLEET_FEAT" 'git push -n origin feature/w1-x'               'push -n is --dry-run, not --no-verify'
allow "$H" "$FLEET_FEAT" 'git merge -n feature/w1-x'                     'merge -n is --no-stat, not --no-verify'
allow "$H" "$FLEET_FEAT" 'git commit -m "-n"'                            'R2-P2: -n as the MESSAGE is not a flag'
allow "$H" "$FLEET_FEAT" 'git commit -m "-n" -a'                         'R2-P2: message operand then real flag'
allow "$H" "$FLEET_FEAT" 'git commit -mn'                                'R2-P2: cluster value — message is n'
allow "$H" "$FLEET_FEAT" 'git commit --fixup HEAD~1 -m "x"'              'R2-P2: value-taking long opt operand'
allow "$H" "$FLEET_FEAT" 'git commit --gpg-sign -m "x"'                  'R3: bare --gpg-sign commit is fine'
allow "$H" "$FLEET_FEAT" 'git commit -S -m "x"'                          'R3: -S sign flag is fine'
allow "$H" "$FLEET_FEAT" 'git commit -Sn -m "x"'                         'R3: -Sn is keyid n, not no-verify'

# ---------------------------------------------------------------------------
# block-destructive-git.sh — A4 (+refspec), A5 (--h prefix), A6 (dot variants), A9
# ---------------------------------------------------------------------------
H=block-destructive-git.sh
block "$H" "$FLEET_FEAT" 'git push --force origin feature/w1-x'          'baseline: --force'
block "$H" "$FLEET_FEAT" 'git push origin feature/w1-x --force'          'baseline: trailing --force'
block "$H" "$FLEET_FEAT" 'git push -f origin feature/w1-x'               'baseline: -f'
block "$H" "$FLEET_FEAT" 'git push origin +HEAD:feature/x'               'A4: leading-+ refspec force'
block "$H" "$FLEET_FEAT" 'git push origin +feature/x'                    'A4: leading-+ bare refspec'
block "$H" "$FLEET_FEAT" 'git push origin "+HEAD:feature/x"'             'PR11-P1: quoted + refspec'
block "$H" "$FLEET_FEAT" 'git push origin feature/x "--force"'           'PR11-P1: quoted force flag'
allow "$H" "$FLEET_FEAT" 'git push --force-with-lease origin feature/w1-x' 'allowed: force-with-lease'
allow "$H" "$FLEET_FEAT" 'git push --force-w origin feature/w1-x'        'allowed: f-w-l unambiguous prefix'
block "$H" "$FLEET_FEAT" 'git push --force-with-lease origin +HEAD:feature/x' 'A4: +refspec even with f-w-l'
block "$H" "$FLEET_FEAT" '(git reset --hard)'                            'R2: closing paren glued to last token'
block "$H" "$FLEET_FEAT" '(git push origin feature/x --force)'           'R2: closing paren after force flag'
block "$H" "$FLEET_FEAT" 'env -S "git push --force origin feature/x"'    'R4: env -S command string'
block "$H" "$FLEET_FEAT" '"git" reset --hard HEAD~1'                     'R4: quoted command word'
block "$H" "$FLEET_FEAT" 'bash -c "git push --force origin feature/x"'   'R5: bash -c payload'
block "$H" "$FLEET_FEAT" 'if git reset --hard; then :; fi'              'R5: control keyword before reset'
block "$H" "$FLEET_FEAT" 'git push origin $'\''+master'\'''             'R6: ANSI-C $'\''...'\'' forced refspec'
block "$H" "$FLEET_FEAT" 'git push $'\''--force'\'' origin feature/x'    'R6: ANSI-C $'\''...'\'' force flag'
block "$H" "$FLEET_FEAT" 'env -u GIT_DIR git push --force origin feature/x' 'R2: env -u wrapper + force'
block "$H" "$FLEET_FEAT" 'git reset --hard HEAD~1'                       'baseline: reset --hard'
block "$H" "$FLEET_FEAT" 'git reset --h HEAD~1'                          'A5: --h prefix'
block "$H" "$FLEET_FEAT" 'git reset --ha HEAD~1'                         'A5: --ha prefix'
allow "$H" "$FLEET_FEAT" 'git reset --soft HEAD~1'                       'allowed: reset --soft'
allow "$H" "$FLEET_FEAT" 'git reset --help'                              'FP guard: --help is not --hard'
block "$H" "$FLEET_FEAT" 'git checkout .'                                'baseline: checkout dot'
block "$H" "$FLEET_FEAT" 'git checkout . '                               'A6: trailing space'
block "$H" "$FLEET_FEAT" 'git checkout ./'                               'A6: dot-slash'
block "$H" "$FLEET_FEAT" 'git checkout -- .'                             'A6: dashdash dot'
block "$H" "$FLEET_FEAT" 'git restore .'                                 'A6: restore dot'
block "$H" "$FLEET_FEAT" 'git restore ./'                                'A6: restore dot-slash'
block "$H" "$FLEET_FEAT" 'git checkout HEAD -- .'                        'A6: checkout HEAD -- .'
block "$H" "$FLEET_FEAT" 'git restore :/'                                'A6-class: repo-root pathspec'
allow "$H" "$FLEET_FEAT" 'git checkout -b feature/w1-new'                'allowed: branch create'
allow "$H" "$FLEET_FEAT" 'git checkout feature/w1-x'                     'allowed: branch switch'
allow "$H" "$FLEET_FEAT" 'git checkout .github/workflows'                'FP guard: path starting with dot'
allow "$H" "$FLEET_FEAT" 'git restore src/file.ts'                       'allowed: single-file restore'
block "$H" "$FLEET_FEAT" 'git clean -xdf'                                'baseline: clean force'
allow "$H" "$FLEET_FEAT" 'git clean -n'                                  'allowed: clean dry-run'
block "$H" "$FLEET_FEAT" 'cd wt && git push -f origin feature/x'         'A1-class prefix + force'
allow "$H" "$FLEET_FEAT" 'echo "git push --force is banned"'             'A9: force literal in echo'
allow "$H" "$FLEET_FEAT" 'grep -r "git reset --hard" docs/'              'A9: reset literal in grep'
allow "$H" "$FLEET_FEAT" 'git commit -m "block git push --force bypass"' 'A9: force literal in -m'

# ---------------------------------------------------------------------------
# block-gh-merge.sh — A10 (non-POSIX \s), block-all hardcoded
# ---------------------------------------------------------------------------
H=block-gh-merge.sh
block "$H" "$FLEET_FEAT" 'gh pr merge 5'                                 'baseline: merge by number'
block "$H" "$FLEET_FEAT" '/usr/bin/gh pr merge 5'                        'R3: path-qualified gh'
block "$H" "$FLEET_FEAT" '"gh" pr merge 5'                              'R4: quoted command word'
block "$H" "$FLEET_FEAT" 'env -S "gh pr merge 5"'                       'R4: env -S command string'
block "$H" "$FLEET_FEAT" 'bash -c "gh pr merge 5"'                      'R5: bash -c payload'
block "$H" "$FLEET_FEAT" 'if gh pr merge 5; then :; fi'                 'R5: control keyword before merge'
block "$H" "$FLEET_FEAT" 'gh pr merge'                                   'bare merge (block-all)'
block "$H" "$FLEET_FEAT" 'gh pr merge --admin 5'                         'merge --admin'
block "$H" "$FLEET_FEAT" 'cd x && gh pr merge 5'                         'A1-class prefix'
block "$H" "$PLAIN" 'gh pr merge 5'                                      'block-all applies everywhere'
allow "$H" "$FLEET_FEAT" 'gh pr view 5'                                  'allowed: pr view'
allow "$H" "$FLEET_FEAT" 'gh pr create --title x --body-file /tmp/b.md'  'allowed: pr create'
allow "$H" "$FLEET_FEAT" 'echo "gh pr merge"'                            'A9-class: literal in echo'

# ---------------------------------------------------------------------------
# block-rebase-interactive.sh — the raw-COMMAND cross-matching FP class
# ---------------------------------------------------------------------------
H=block-rebase-interactive.sh
block "$H" "$FLEET_FEAT" 'git rebase -i HEAD~3'                          'baseline: rebase -i'
block "$H" "$FLEET_FEAT" 'git rebase --interactive main'                 'baseline: rebase --interactive'
block "$H" "$FLEET_FEAT" 'git add -p'                                    'baseline: add --patch'
block "$H" "$FLEET_FEAT" 'git checkout -p src/file.ts'                   'baseline: checkout --patch'
allow "$H" "$FLEET_FEAT" 'git checkout -b feature/w1-z && mkdir -p somedir' 'FP: -p belongs to mkdir, not git'
allow "$H" "$FLEET_FEAT" 'git rebase main'                               'allowed: non-interactive rebase'
allow "$H" "$FLEET_FEAT" 'git add -A && npm install -i-dont-exist'       'FP guard: -i outside the git segment'
allow "$H" "$FLEET_FEAT" 'echo "git rebase -i"'                          'A9-class: literal in echo'

# ---------------------------------------------------------------------------
# block-file-redirect.sh — A7 (non-redirect writers) + existing redirect coverage
# Runs in the MAIN checkout of a fleet-ACTIVE repo (that is its enforcement zone).
# ---------------------------------------------------------------------------
H=block-file-redirect.sh
block "$H" "$FLEET_FEAT" 'echo x > src/file.ts'                          'baseline: redirect into repo'
block "$H" "$FLEET_FEAT" 'echo x >| src/file.ts'                         'clobber redirect into repo'
block "$H" "$FLEET_FEAT" 'cat /tmp/x | tee src/file.ts'                  'baseline: tee into repo'
block "$H" "$FLEET_FEAT" "sed -i 's/1/2/' src/file.ts"                   'A7: sed -i (GNU form)'
block "$H" "$FLEET_FEAT" "sed -i '' -e 's/1/2/' src/file.ts"             'A7: sed -i (BSD form)'
block "$H" "$FLEET_FEAT" 'cp /tmp/x src/file.ts'                         'A7: cp into repo'
block "$H" "$FLEET_FEAT" 'cp /tmp/x "src/my file.ts"'                    'A7: cp into repo, quoted spaced path'
block "$H" "$FLEET_FEAT" 'mv /tmp/x src/file.ts'                         'A7: mv into repo'
block "$H" "$FLEET_FEAT" 'dd if=/dev/zero of=src/file.ts bs=1 count=1'   'A7: dd of= into repo'
block "$H" "$FLEET_FEAT" 'sponge src/file.ts'                            'A7: sponge into repo'
block "$H" "$FLEET_FEAT" 'cp -t src /tmp/x'                              'PR11-P2: cp -t DIR'
block "$H" "$FLEET_FEAT" 'cp -tsrc /tmp/x'                               'PR11-P2: cp -tDIR attached'
block "$H" "$FLEET_FEAT" 'mv --target-directory=src /tmp/x'              'PR11-P2: mv --target-directory='
block "$H" "$FLEET_FEAT" 'cp --target-directory src /tmp/x'              'PR11-P2: cp --target-directory DIR'
allow "$H" "$FLEET_FEAT" 'cp -t /tmp src/file.ts'                        'PR11-P2: -t OUTSIDE repo allowed'
block "$H" "$FLEET_FEAT" 'env -i cp /tmp/x src/file.ts'                  'R3: env -i before writer'
block "$H" "$FLEET_FEAT" 'env -u FOO mv /tmp/x src/file.ts'              'R3: env -u NAME before writer'
block "$H" "$FLEET_FEAT" 'sudo -u root cp /tmp/x src/file.ts'            'R3-class: sudo -u before writer'
block "$H" "$FLEET_FEAT" '/bin/cp /tmp/x src/file.ts'                    'R3-class: path-qualified writer'
block "$H" "$FLEET_FEAT" '"cp" /tmp/x src/file.ts'                      'R4: quoted writer command word'
block "$H" "$FLEET_FEAT" 'c"p" /tmp/x src/file.ts'                      'R4: split-quoted writer command word'
block "$H" "$FLEET_FEAT" 'env -S "cp /tmp/x src/file.ts"'               'R4: env -S writer command string'
block "$H" "$FLEET_FEAT" 'if cp /tmp/x src/file.ts; then :; fi'         'R5: control keyword before writer'
block "$H" "$FLEET_FEAT" 'bash -c "cp /tmp/x src/file.ts"'              'R5: bash -c writer payload'
block "$H" "$FLEET_FEAT" 'cp -vtsrc /tmp/x'                             'R6: clustered attached -t (cp -vtsrc)'
block "$H" "$FLEET_FEAT" 'cp -rt src /tmp/x'                            'R6: cluster ending in t + dir arg'
allow "$H" "$FLEET_FEAT" 'cp -vt /tmp /tmp/x src/file.ts'              'R6: clustered -t OUTSIDE repo (allow)'
allow "$H" "$FLEET_FEAT" 'cp src/file.ts /tmp/out.ts'                    'allowed: copy OUT of repo'
allow "$H" "$FLEET_FEAT" 'mv src/file.ts /tmp/out.ts'                    'allowed: move OUT of repo (read+delete, not write)'
allow "$H" "$FLEET_FEAT" "sed -i 's/1/2/' /tmp/outside.txt"              'allowed: sed -i outside repo'
allow "$H" "$FLEET_FEAT" "sed -n 'p' src/file.ts"                        'allowed: sed without -i'
allow "$H" "$FLEET_FEAT" 'sed -i -f src/edit.sed /tmp/outside.txt'       'R7: sed -f script is not an edit target'
allow "$H" "$FLEET_FEAT" 'sed -i -e s/a/b/ /tmp/outside.txt'             'R7: sed -e expression, edit outside repo'
block "$H" "$FLEET_FEAT" 'sed -i -f /tmp/x.sed src/file.ts'             'R7: sed -f but real edit target in repo'
allow "$H" "$FLEET_FEAT" 'echo x > /tmp/y.txt'                           'allowed: redirect outside repo'
allow "$H" "$FLEET_FEAT" 'grep -n export src/file.ts'                    'allowed: read-only'
allow "$H" "$FLEET_FEAT" 'echo "cp a src/file.ts"'                       'A9-class: writer literal in echo'
allow "$H" "$FLEET_WT" 'echo x > src/file.ts'                            'allowed: write inside a WORKTREE'
allow "$H" "$PLAIN" 'sed -i "s/1/2/" src/file.ts'                        'allowed: non-fleet repo'

# ---------------------------------------------------------------------------
# check-work-registration.sh / check-branch-prefix.sh — must survive the
# segment-matching change (commit detection incl. prefixes, no regressions)
# ---------------------------------------------------------------------------
H=check-work-registration.sh
allow "$H" "$FLEET_FEAT" 'git commit -m "x"'                             'registered branch commits fine'
block "$H" "$FLEET_UNREG" 'git commit -m "x"'                            'unregistered feature branch blocked'
block "$H" "$FLEET_UNREG" 'cd wt && git commit -m "x"'                   'A1-class prefix still detected'
allow "$H" "$PLAIN" 'git commit -m "x"'                                  'non-fleet repo skips'

H=check-branch-prefix.sh
allow "$H" "$FLEET_FEAT" 'git commit -m "x"'                             'w1 branch, no window-id file: skip'
allow "$H" "$PLAIN" 'git commit -m "x"'                                  'non-fleet repo skips'

# ---------------------------------------------------------------------------
# session-guard.js — A11 (over-counting via nested type fields; size fast-path)
# ---------------------------------------------------------------------------
if command -v node >/dev/null 2>&1 && [ -f "$SESSION_GUARD" ]; then
  sg_case() { # $1=transcript $2=session_id $3=expect_output(yes|no) $4=label
    local out
    out=$(printf '{"transcript_path":"%s","session_id":"%s"}' "$1" "$2" | node "$SESSION_GUARD" 2>/dev/null)
    local got=no; [ -n "$out" ] && got=yes
    if [ "$got" = "$3" ]; then
      PASS=$((PASS+1)); printf 'ok   %-28s %-6s %s\n' "[session-guard.js]" "out=$3" "$4"
    else
      FAIL=$((FAIL+1)); printf 'FAIL %-28s want-output=%s got=%s %s\n' "[session-guard.js]" "$3" "$got" "$4"
    fi
  }
  SGID="suite-$$-$RANDOM"

  # Small transcript (under the size gate) → no nudge, no full read needed
  T1="$TMP/t-small.jsonl"
  for i in 1 2 3; do echo '{"type":"assistant","message":{}}'; done > "$T1"
  sg_case "$T1" "$SGID-small" no 'small transcript: silent'

  # Large transcript, 450 REAL top-level assistant lines → gentle nudge fires
  T2="$TMP/t-real.jsonl"
  PAD=$(printf 'x%.0s' $(seq 1 4000))
  { for i in $(seq 1 450); do echo "{\"type\":\"assistant\",\"pad\":\"$PAD\"}"; done; } > "$T2"
  sg_case "$T2" "$SGID-real" yes 'A11: 450 real assistant turns: nudges'

  # Large transcript, only 10 real assistant lines but 600 nested
  # "type":"assistant" objects inside tool results → must stay SILENT
  T3="$TMP/t-nested.jsonl"
  {
    for i in $(seq 1 10); do echo "{\"type\":\"assistant\",\"pad\":\"$PAD\"}"; done
    for i in $(seq 1 600); do echo "{\"type\":\"user\",\"toolUseResult\":{\"messages\":[{\"type\":\"assistant\",\"pad\":\"$PAD\"}]}}"; done
  } > "$T3"
  sg_case "$T3" "$SGID-nested" no 'A11: nested assistant objects must NOT count'
else
  echo 'skip [session-guard.js] node or script not found'
fi

# ---------------------------------------------------------------------------
# B1 — settings deny rule must not swallow --force-with-lease
# ---------------------------------------------------------------------------
b1_case() { # $1=expect(present|absent) $2=literal $3=label
  local found=absent
  grep -qF "$2" "$SETTINGS_FILE" 2>/dev/null && found=present
  if [ "$found" = "$1" ]; then
    PASS=$((PASS+1)); printf 'ok   %-28s %-6s %s\n' "[settings]" "$1" "$3"
  else
    FAIL=$((FAIL+1)); printf 'FAIL %-28s want=%s got=%s %s (%s)\n' "[settings]" "$1" "$found" "$3" "$SETTINGS_FILE"
  fi
}
b1_case absent  '"Bash(git push --force*)"'  'B1: over-broad force* deny removed'
b1_case present '"Bash(git push --force)"'   'B1: exact --force still denied'
b1_case present '"Bash(git push --force *)"' 'B1: --force <args> still denied'

# ---------------------------------------------------------------------------
echo
echo "hooks under test: $HOOKS_DIR"
echo "settings under test: $SETTINGS_FILE"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
