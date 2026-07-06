#!/bin/bash
# advisory-hooks.test.sh — tests for the two Theme-E advisory controls:
#   pr-ready-gate.js   (E3: PR-Ready gate — verify mode + Stop-hook mode)
#   check-fix-landed.sh (E5: orphaned-fix detector, PostToolUse)
#
# Both are ADVISORY (never wedge a session) and both call `gh` — so the tests
# stub `gh` on PATH with canned responses and drive TMPDIR to an isolated marker
# dir. Run before AND after any edit to either file.
#
#   bash platform/tests/advisory-hooks.test.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="${HOOKS_DIR:-$REPO/platform/global/hooks}"
GATE="${GATE:-$REPO/platform/global/pr-ready-gate.js}"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s\n     %s\n' "$1" "$2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
GITC="git -c user.email=t@t -c user.name=t -c commit.gpgsign=false"
export TMPDIR="$TMP/tmpdir"; mkdir -p "$TMPDIR"   # isolates pr-ready marker dir

# ── gh stub: reads canned response from $GH_OUT / exit from $GH_RC ──────────────
STUB="$TMP/bin"; mkdir -p "$STUB"
cat > "$STUB/gh" <<'SH'
#!/bin/bash
# Canned gh. $GH_MODE selects behavior; all git-independent. URLs are real github.com
# form so check-fix-landed can parse owner/repo for the pr-ready invalidate call.
sub="$1 $2"
case "$GH_MODE" in
  nopr)     [ "$sub" = "pr list" ] && { echo '[]'; exit 0; } ;;
  open)     [ "$sub" = "pr list" ] && { echo "[{\"number\":9,\"state\":\"OPEN\",\"baseRefName\":\"staging\",\"url\":\"https://github.com/o/r/pull/9\"}]"; exit 0; } ;;
  merged)   [ "$sub" = "pr list" ] && { echo "[{\"number\":9,\"state\":\"MERGED\",\"baseRefName\":\"master\",\"url\":\"https://github.com/o/r/pull/9\"}]"; exit 0; } ;;
  closed)   [ "$sub" = "pr list" ] && { echo "[{\"number\":9,\"state\":\"CLOSED\",\"baseRefName\":\"master\",\"url\":\"https://github.com/o/r/pull/9\"}]"; exit 0; } ;;
  fail)     [ "$sub" = "pr list" ] && { echo "gh: could not authenticate" >&2; exit 4; } ;;   # network/auth failure
  # verify-mode paths: `pr checks` green; `api graphql --paginate` emits one unresolved
  # count PER PAGE (two pages here) so the sum exercises pagination.
  verify0)  [ "$sub" = "pr checks" ] && { echo "all green"; exit 0; }; [ "$sub" = "api graphql" ] && { printf '0\n0\n'; exit 0; } ;;
  verify1)  [ "$sub" = "pr checks" ] && { echo "all green"; exit 0; }; [ "$sub" = "api graphql" ] && { printf '0\n1\n'; exit 0; } ;;
esac
exit 0
SH
chmod +x "$STUB/gh"

# =============================================================================
# pr-ready-gate.js — VERIFY MODE arg validation (no gh needed)
# =============================================================================
node "$GATE" verify 2>/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "verify: missing args → exit 2" || bad "verify: missing args" "rc=$rc (want 2)"
node "$GATE" verify ownerrepo 12 2>/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok "verify: malformed owner/repo → exit 2" || bad "verify: malformed target" "rc=$rc (want 2)"

# =============================================================================
# pr-ready-gate.js — STOP-HOOK MODE decision logic
# =============================================================================
mk_transcript() { # $1=file  $2=assistant text
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":%s}]}}\n' \
    "$(printf '%s' "$2" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" > "$1"
}
stop_decision() { # $1=transcript $2=stop_hook_active(true|false)  → echo stdout
  printf '{"transcript_path":"%s","session_id":"s","stop_hook_active":%s}' "$1" "$2" | node "$GATE" 2>/dev/null
}
mark_pass() { # $1=owner $2=repo $3=pr  — write a FRESH pass marker
  local d="$TMPDIR/claude-pr-ready"; mkdir -p "$d"
  printf '{"owner":"%s","repo":"%s","pr":%s,"verdict":"PASS","ts":%s}' \
    "$1" "$2" "$3" "$(node -e 'process.stdout.write(String(Date.now()))')" > "$d/${1}_${2}_${3}.json"
}
clear_markers() { rm -rf "$TMPDIR/claude-pr-ready"; }

T="$TMP/t.jsonl"

# claim + PR reference + NO marker → BLOCK
clear_markers
mk_transcript "$T" "The staging PR is ready to merge: https://github.com/o/r/pull/9"
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: ready+PR, no marker → block" || bad "stop: ready+PR, no marker" "out=$out"

# same claim WITH a fresh pass marker for #9 → ALLOW (no output)
clear_markers; mark_pass o r 9
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: ready+PR, fresh marker → allow" || bad "stop: fresh marker should allow" "out=$out"

# stale marker (ts old) → BLOCK
clear_markers; d="$TMPDIR/claude-pr-ready"; mkdir -p "$d"
printf '{"owner":"o","repo":"r","pr":9,"verdict":"PASS","ts":1}' > "$d/o_r_9.json"
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: stale marker → block" || bad "stop: stale marker" "out=$out"

# FAIL-verdict marker (not PASS) → BLOCK
clear_markers; mkdir -p "$d"
printf '{"owner":"o","repo":"r","pr":9,"verdict":"FAIL","ts":%s}' "$(node -e 'process.stdout.write(String(Date.now()))')" > "$d/o_r_9.json"
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: FAIL marker → block" || bad "stop: FAIL marker" "out=$out"

# MULTI-PR claim, only ONE named PR verified → BLOCK. Every named PR must have its own
# fresh marker; a sibling's marker must not carry the unverified one through (outside-
# review P2.1 — staging #7 verified, prod #9 is the actual unverified claim).
clear_markers; mark_pass o r 7
mk_transcript "$T" "PR #7 and PR #9 are both ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: multi-PR, one unverified → block" || bad "stop: multi-PR one unverified" "out=$out"

# same multi-PR claim with BOTH named PRs verified → ALLOW
clear_markers; mark_pass o r 7; mark_pass o r 9
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: multi-PR, both verified → allow" || bad "stop: multi-PR both verified should allow" "out=$out"

# CROSS-REPO collision: a /pull/ URL claim for repoA#9 with a fresh marker only for a
# DIFFERENT repo's #9 → BLOCK. PR numbers collide across the 3 fleet repos; a repo-
# qualified claim must match the marker's repo (Codex P1).
clear_markers; mark_pass otherowner otherrepo 9
mk_transcript "$T" "Ready to merge: https://github.com/theowner/therepo/pull/9"
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: cross-repo #9 marker → block" || bad "stop: cross-repo collision" "out=$out"

# same URL claim WITH a same-repo marker → ALLOW
clear_markers; mark_pass theowner therepo 9
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: URL claim, same-repo marker → allow" || bad "stop: same-repo URL should allow" "out=$out"

# bare "Done — PR #9 is open" (readiness = bare 'done') + PR context + no marker → BLOCK
clear_markers
mk_transcript "$T" "Done — PR #9 is open."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: bare 'Done' + PR ref → block" || bad "stop: bare done + PR" "out=$out"

# plain 'done' with NO PR context → ALLOW (bare-done must not over-trigger)
clear_markers
mk_transcript "$T" "Done reviewing the code; everything reads fine."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: bare 'done', no PR → allow" || bad "stop: bare done over-trigger" "out=$out"

# invalidate mode clears a fresh marker → a subsequent claim BLOCKS (Codex P1 head-staleness)
clear_markers; mark_pass o r 9
node "$GATE" invalidate o/r 9 >/dev/null 2>&1
mk_transcript "$T" "PR #9 is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "invalidate: marker cleared → block" || bad "stop: invalidate unit" "out=$out"

# verify mode, PAGINATED unresolved threads: an unresolved thread on page 2 → FAIL(1)
clear_markers
GH_MODE=verify1 PATH="$STUB:$PATH" node "$GATE" verify o/r 9 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "verify: paginated unresolved (page 2) → FAIL(1)" || bad "verify paginate FAIL" "rc=$rc"

# verify mode, all pages resolved + checks green → PASS(0) marker written
clear_markers
GH_MODE=verify0 PATH="$STUB:$PATH" node "$GATE" verify o/r 9 >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && [ -f "$TMPDIR/claude-pr-ready/o_r_9.json" ]; } && ok "verify: paginated all-resolved → PASS(0)" || bad "verify paginate PASS" "rc=$rc"

# no PR reference (plain 'done') → ALLOW even with no marker
clear_markers
mk_transcript "$T" "All done — the refactor is complete and tests pass."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: no PR context → allow" || bad "stop: plain done should allow" "out=$out"

# readiness but no PR ref → ALLOW
mk_transcript "$T" "The feature is ready and working well."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: ready w/o PR ref → allow" || bad "stop: ready w/o PR should allow" "out=$out"

# stop_hook_active=true → never loop (ALLOW) even on a bare claim w/ no marker
clear_markers
mk_transcript "$T" "PR #9 is ready to ship."
out=$(stop_decision "$T" true)
[ -z "$out" ] && ok "stop: stop_hook_active → allow (no loop)" || bad "stop: must not loop" "out=$out"

# claim naming PR #9 but only a marker for #7 → BLOCK (wrong PR unverified)
clear_markers; mark_pass o r 7
mk_transcript "$T" "PR #9 is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: marker for other PR → block" || bad "stop: wrong-PR marker" "out=$out"

# outside-review P1: claim about #9 with a "closes #7" tail + fresh marker for #7 →
# BLOCK (the bare-#N scoop must NOT let the #7 marker satisfy the #9 claim)
clear_markers; mark_pass o r 7
mk_transcript "$T" "PR #9 is ready to merge (closes #7)."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: #9 claim, #7 marker via 'closes #7' → block" || bad "stop: P1 number-scoop" "out=$out"

# outside-review P2: PR context but NO extractable number + a fresh marker for some PR →
# BLOCK (cannot tie the claim to a marker; make the model name the PR)
clear_markers; mark_pass o r 9
mk_transcript "$T" "The staging PR is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: PR context, no number → block" || bad "stop: P2 no-number auto-pass" "out=$out"

# malformed transcript → fail open (ALLOW, no crash)
out=$(printf '{"transcript_path":"/nope","session_id":"s"}' | node "$GATE" 2>/dev/null); rc=$?
{ [ -z "$out" ] && [ "$rc" -eq 0 ]; } && ok "stop: missing transcript → fail open" || bad "stop: fail open" "out=$out rc=$rc"

# =============================================================================
# check-fix-landed.sh — needs a fixture repo + gh stub + tokenizer
# =============================================================================
HOOK="$HOOKS_DIR/check-fix-landed.sh"
FX="$TMP/fx"; mkdir -p "$FX"; git -C "$FX" init -q -b feature/w1-x
echo a > "$FX/f"; git -C "$FX" add -A; $GITC -C "$FX" commit -qm seed
# give it a fake origin + tracking so origin/<branch> resolves
BARE="$TMP/bare.git"; git init -q --bare "$BARE"
git -C "$FX" remote add origin "$BARE"; git -C "$FX" push -q -u origin feature/w1-x 2>/dev/null

feed() { # $1=cmd → run the PostToolUse hook in $FX with the gh stub on PATH
  json=$(CMD_STR="$1" perl -e 'my $c=$ENV{CMD_STR}; $c=~s/\\/\\\\/g; $c=~s/"/\\"/g; print "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$c\"}}";')
  printf '%s' "$json" | ( cd "$FX" && PATH="$STUB:$PATH" GH_MODE="$GH_MODE" bash "$HOOK" ) 2>&1; echo "rc=$?"
}

# not a git command → silent, exit 0
GH_MODE=nopr; out=$(feed 'ls -la')
echo "$out" | grep -q 'rc=0' && [ "$(echo "$out" | grep -c fix-landing)" = 0 ] && ok "cfl: non-git → silent" || bad "cfl: non-git" "$out"

# commit on a branch with NO PR → benign (commit is normal early work), exit 0
GH_MODE=nopr; out=$(feed 'git commit -m x')
echo "$out" | grep -q 'rc=0' && ok "cfl: commit no-PR → allow" || bad "cfl: commit no-PR" "$out"

# PUSH on a branch with NO PR → ⚠️ orphan warning, exit 2
GH_MODE=nopr; out=$(feed 'git push origin feature/w1-x')
{ echo "$out" | grep -q 'rc=2' && echo "$out" | grep -q 'NO open PR'; } && ok "cfl: push no-PR → warn(2)" || bad "cfl: push no-PR" "$out"

# push, PR OPEN, HEAD on remote → ✓ exit 0
GH_MODE=open; out=$(feed 'git push origin feature/w1-x')
{ echo "$out" | grep -q 'rc=0' && echo "$out" | grep -q 'OPEN PR #9'; } && ok "cfl: push open-PR on remote → ok" || bad "cfl: push open-PR" "$out"

# push, PR MERGED but HEAD not in base (base 'master' doesn't exist in bare) → 🚨 orphan, exit 2
GH_MODE=merged; out=$(feed 'git push origin feature/w1-x')
{ echo "$out" | grep -q 'rc=2' && echo "$out" | grep -q 'ORPHANED FIX'; } && ok "cfl: push merged-PR excl HEAD → orphan(2)" || bad "cfl: merged orphan" "$out"

# push, PR CLOSED unmerged → 🚨 exit 2
GH_MODE=closed; out=$(feed 'git push origin feature/w1-x')
{ echo "$out" | grep -q 'rc=2' && echo "$out" | grep -q 'CLOSED unmerged'; } && ok "cfl: push closed-PR → warn(2)" || bad "cfl: closed PR" "$out"

# push, but `gh pr list` FAILS (auth/network/timeout, non-zero rc) → must stay SILENT,
# not cry a false "NO open PR" orphan (Codex P2: a lookup failure ≠ a successful []).
GH_MODE=fail; out=$(feed 'git push origin feature/w1-x')
{ echo "$out" | grep -q 'rc=0' && [ "$(echo "$out" | grep -c 'NO open PR')" = 0 ]; } && ok "cfl: gh lookup fails → silent(0)" || bad "cfl: gh-fail false orphan" "$out"

# push resolving an OPEN PR invalidates that PR's PR-Ready marker (Codex P1 head-staleness):
# the pushed head is unverified until re-verify, so the stale PASS must be cleared.
clear_markers; mark_pass o r 9
GH_MODE=open; feed 'git push origin feature/w1-x' >/dev/null 2>&1
[ ! -f "$TMPDIR/claude-pr-ready/o_r_9.json" ] && ok "cfl: push invalidates pr-ready marker" || bad "cfl: push should invalidate marker" "marker still present"

# commit while standing ON a deploy branch → out of scope, silent exit 0
git -C "$FX" checkout -q -b master 2>/dev/null || git -C "$FX" checkout -q master
GH_MODE=nopr; out=$(feed 'git commit -m x')
{ echo "$out" | grep -q 'rc=0' && [ "$(echo "$out" | grep -c fix-landing)" = 0 ]; } && ok "cfl: deploy branch → silent" || bad "cfl: deploy branch" "$out"
git -C "$FX" checkout -q feature/w1-x

# heredoc: a commit whose -F - body quotes `git push` must be seen as a COMMIT, not
# a push (the original motivating bug — the hook firing on its own commit). No PR →
# a commit is benign early work (exit 0), NOT the push orphan-warning.
GH_MODE=nopr; out=$(feed $'git commit -F - <<EOF\nfix: stuff\ngit push origin master\nEOF')
{ echo "$out" | grep -q 'rc=0' && [ "$(echo "$out" | grep -c 'NO open PR')" = 0 ]; } && ok "cfl: heredoc body 'git push' → commit not push" || bad "cfl: heredoc action" "$out"

# `cd repo && git push` wrapper resolves via the tokenizer (no PR) → warn(2)
GH_MODE=nopr; out=$(feed "cd \"$FX\" && git push origin feature/w1-x")
{ echo "$out" | grep -q 'rc=2' && echo "$out" | grep -q 'NO open PR'; } && ok "cfl: cd-wrapper push resolves" || bad "cfl: cd-wrapper" "$out"

# gh absent → silent (can't check) : simulate by empty PATH
out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/w1-x"}}' | ( cd "$FX" && PATH="/usr/bin:/bin" bash "$HOOK" ) 2>&1; echo "rc=$?")
echo "$out" | grep -q 'rc=0' && ok "cfl: no gh → silent(0)" || bad "cfl: no gh" "$out"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
