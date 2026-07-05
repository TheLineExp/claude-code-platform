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
block "$H" "$FLEET_FEAT" 'git push origin HEAD:staging'                  'baseline: HEAD:staging'
block "$H" "$FLEET_FEAT" 'git push origin HEAD:refs/heads/staging'       'A3: fully-qualified refspec'
block "$H" "$FLEET_FEAT" 'git push origin refs/heads/master'             'A3: fully-qualified source-less'
block "$H" "$FLEET_FEAT" 'git push origin +master'                       'A3/A4: forced protected refspec'
block "$H" "$FLEET_FEAT" 'git push origin --delete staging'              'protected-branch remote delete'
allow "$H" "$FLEET_FEAT" 'git push origin feature/staging-fix'           'FP guard: branch NAMED staging-ish'
allow "$H" "$FLEET_FEAT" 'git push origin feature/w1-x'                  'normal feature push'
allow "$H" "$FLEET_FEAT" 'echo "git push origin master"'                 'A9-class: literal in echo'
allow "$H" "$FLEET_FEAT" 'git commit -m "true; git push origin master"'  'A9-class: literal in -m'
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
allow "$H" "$FLEET_FEAT" 'git commit -am "x"'                            'FP guard: -am has no n'
allow "$H" "$FLEET_FEAT" 'git commit -m "document --no-verify usage"'    'A9: flag literal inside -m'
allow "$H" "$FLEET_FEAT" 'grep -rn -- --no-verify hooks/'                'A9: flag literal in grep'
allow "$H" "$FLEET_FEAT" 'echo "--no-verify is banned"'                  'A9: flag literal in echo'
allow "$H" "$FLEET_FEAT" 'git push -n origin feature/w1-x'               'push -n is --dry-run, not --no-verify'
allow "$H" "$FLEET_FEAT" 'git merge -n feature/w1-x'                     'merge -n is --no-stat, not --no-verify'

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
allow "$H" "$FLEET_FEAT" 'cp src/file.ts /tmp/out.ts'                    'allowed: copy OUT of repo'
allow "$H" "$FLEET_FEAT" 'mv src/file.ts /tmp/out.ts'                    'allowed: move OUT of repo (read+delete, not write)'
allow "$H" "$FLEET_FEAT" "sed -i 's/1/2/' /tmp/outside.txt"              'allowed: sed -i outside repo'
allow "$H" "$FLEET_FEAT" "sed -n 'p' src/file.ts"                        'allowed: sed without -i'
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
