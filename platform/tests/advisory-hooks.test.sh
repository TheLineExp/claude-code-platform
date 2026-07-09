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
  # pr-list now goes through gh's own --jq, so the stub emits the SAME @tsv rows --jq would
  # ([number, state, baseRefName, url]); `[]` -> no output. URLs stay real github.com form so
  # check-fix-landed can parse owner/repo for the pr-ready invalidate call.
  nopr)     [ "$sub" = "pr list" ] && { exit 0; } ;;                                                  # [] -> --jq emits nothing
  open)     [ "$sub" = "pr list" ] && { printf '9\tOPEN\tstaging\thttps://github.com/o/r/pull/9\n';    exit 0; } ;;
  merged)   [ "$sub" = "pr list" ] && { printf '9\tMERGED\tmaster\thttps://github.com/o/r/pull/9\n';   exit 0; } ;;
  merged_nofetch) [ "$sub" = "pr list" ] && { printf '9\tMERGED\tghost-base\thttps://github.com/o/r/pull/9\n'; exit 0; } ;;   # base not on remote → fetch fails
  closed)   [ "$sub" = "pr list" ] && { printf '9\tCLOSED\tmaster\thttps://github.com/o/r/pull/9\n';   exit 0; } ;;
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
# chunk B6: a bare `#N` is scoped to the repo the Stop hook runs in. These helpers let a test
# pin that cwd to a known repo (mk_gitrepo) and feed it to the hook (stop_decision_cwd).
mk_gitrepo() { # $1=dir  $2=owner/repo  — throwaway repo whose `origin` is github.com/$2
  mkdir -p "$1"; git -C "$1" init -q; git -C "$1" remote add origin "https://github.com/$2.git" 2>/dev/null
}
stop_decision_cwd() { # $1=transcript $2=stop_hook_active $3=cwd  → echo stdout
  printf '{"transcript_path":"%s","session_id":"s","stop_hook_active":%s,"cwd":"%s"}' "$1" "$2" "$3" | node "$GATE" 2>/dev/null
}

T="$TMP/t.jsonl"

# ── block-biased core: a live readiness token + a referenced PR w/o a fresh marker → BLOCK
# claim + PR reference (URL) + NO marker → BLOCK
clear_markers
mk_transcript "$T" "Ready to merge: https://github.com/o/r/pull/9"
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: ready+PR, no marker → block" || bad "stop: ready+PR, no marker" "out=$out"

# same claim WITH a fresh pass marker for #9 → ALLOW (no output) — verified-ready path
clear_markers; mark_pass o r 9
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: ready+PR, fresh marker → allow" || bad "stop: fresh marker should allow" "out=$out"

# bare "PR #9 is ready" (no URL) + no marker → BLOCK
clear_markers
mk_transcript "$T" "PR #9 is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: bare 'PR #9 is ready', no marker → block" || bad "stop: bare PR ready" "out=$out"

# ── chunk B6: a BARE `#N` is scoped to the CURRENT repo (Stop-hook cwd) ─────────────────
# Before B6 a bare `#N` matched ANY repo's fresh `#N` marker → cross-repo false-PASS. Now a
# bare claim is satisfied ONLY by a marker for the repo the hook runs in; cross-repo ambiguity
# or an undeterminable cwd BLOCK (block-biased). These replace the old repo-blind allow test.

# same-repo ALLOW: fresh marker for theowner/therepo #9 + cwd IN theowner/therepo + bare "#9 ready" → ALLOW
clear_markers; mark_pass theowner therepo 9
mk_gitrepo "$TMP/repo_same" theowner/therepo
mk_transcript "$T" "PR #9 is ready to merge."
out=$(stop_decision_cwd "$T" false "$TMP/repo_same")
[ -z "$out" ] && ok "B6 stop: bare '#9 ready' + same-repo marker (cwd) → allow" || bad "B6 same-repo allow" "out=$out"

# REPRO of the pre-B6 false-PASS → must now BLOCK: a fresh marker exists ONLY for
# reservations#9, but the hook runs in a DIFFERENT repo (platform) and the bare "#9 ready"
# was meant for it. Pre-B6 this rode the reservations#9 marker and PASSED (the empirical hole).
clear_markers; mark_pass TheLineExp fleetmanager-reservations 9
mk_gitrepo "$TMP/repo_other" TheLineExp/claude-code-platform
mk_transcript "$T" "PR #9 is ready to merge."
out=$(stop_decision_cwd "$T" false "$TMP/repo_other")
echo "$out" | grep -q '"decision":"block"' && ok "B6 stop: bare '#9 ready', marker for a DIFFERENT repo → block (repro)" || bad "B6 cross-repo false-PASS repro" "out=$out"

# CROSS-REPO AMBIGUITY → BLOCK: the same bare `#9` has fresh markers under 2 distinct repos.
clear_markers; mark_pass owner1 repoA 9; mark_pass owner2 repoB 9
mk_transcript "$T" "PR #9 is ready to merge."
out=$(stop_decision_cwd "$T" false "$TMP/repo_same")   # cwd=theowner/therepo (neither #9 repo) → block
echo "$out" | grep -q '"decision":"block"' && ok "B6 stop: bare '#9' fresh under 2 repos → block (ambiguous)" || bad "B6 ambiguity block" "out=$out"
mk_gitrepo "$TMP/repo_amb" owner1/repoA
out=$(stop_decision_cwd "$T" false "$TMP/repo_amb")     # cwd MATCHES one of the two → STILL block
echo "$out" | grep -q '"decision":"block"' && ok "B6 stop: bare '#9' under 2 repos, cwd matches one → still block" || bad "B6 ambiguity block (cwd matches one)" "out=$out"

# UNDETERMINABLE cwd → BLOCK (behavior-change note): a fresh marker exists, but the cwd is not
# a git repo, so the bare `#9` can't be scoped to a repo → block (safe).
clear_markers; mark_pass theowner therepo 9
mkdir -p "$TMP/nogit"
mk_transcript "$T" "PR #9 is ready to merge."
out=$(stop_decision_cwd "$T" false "$TMP/nogit")
echo "$out" | grep -q '"decision":"block"' && ok "B6 stop: bare '#9 ready', cwd not a git repo → block" || bad "B6 undeterminable cwd block" "out=$out"

# stale marker (ts old) → BLOCK  (marker machinery unchanged)
clear_markers; d="$TMPDIR/claude-pr-ready"; mkdir -p "$d"
printf '{"owner":"o","repo":"r","pr":9,"verdict":"PASS","ts":1}' > "$d/o_r_9.json"
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: stale marker → block" || bad "stop: stale marker" "out=$out"

# FAIL-verdict marker (not PASS) → BLOCK
clear_markers; mkdir -p "$d"
printf '{"owner":"o","repo":"r","pr":9,"verdict":"FAIL","ts":%s}' "$(node -e 'process.stdout.write(String(Date.now()))')" > "$d/o_r_9.json"
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: FAIL marker → block" || bad "stop: FAIL marker" "out=$out"

# MULTI-PR claim, only ONE named PR verified → BLOCK. Every referenced PR needs its own
# fresh marker; a sibling's marker must not carry the unverified one through (outside-
# review P2.1 — staging #7 verified, prod #9 is the actual unverified claim).
clear_markers; mark_pass o r 7
mk_transcript "$T" "PR #7 and PR #9 are both ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: multi-PR, one unverified → block" || bad "stop: multi-PR one unverified" "out=$out"

# same multi-PR claim with BOTH named PRs verified (same repo as cwd) → ALLOW
clear_markers; mark_pass theowner therepo 7; mark_pass theowner therepo 9
mk_transcript "$T" "PR #7 and PR #9 are both ready to merge."
out=$(stop_decision_cwd "$T" false "$TMP/repo_same")
[ -z "$out" ] && ok "stop: multi-PR, both verified (same-repo cwd) → allow" || bad "stop: multi-PR both verified should allow" "out=$out"

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

# BEHAVIOR CHANGE (block-biased): bare "done" is NOT a readiness token — too overloaded to
# gate without the clause-reasoning this redesign removes. "PR #9 is open" is not a
# ready-claim, so this ALLOWs (old design blocked on bare 'done').
clear_markers
mk_transcript "$T" "Done — PR #9 is open."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: 'Done — PR #9 is open' (no ready token) → allow" || bad "stop: bare-done not a token" "out=$out"

# plain 'done' with NO PR context → ALLOW
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

# no PR reference at all → ALLOW even with a readiness token
clear_markers
mk_transcript "$T" "All done — the refactor is complete and tests pass."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: no PR context → allow" || bad "stop: plain done should allow" "out=$out"

# readiness but no PR ref → ALLOW (rule requires a referenced PR)
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

# outside-review P1: claim about #9 with a "closes #7" tail + fresh marker for #7 → BLOCK.
# Greedy harvest scoops BOTH #9 and #7, but #9 is unmarked → the #7 marker cannot carry #9.
clear_markers; mark_pass o r 7
mk_transcript "$T" "PR #9 is ready to merge (closes #7)."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: #9 claim, #7 marker via 'closes #7' → block" || bad "stop: P1 number-scoop" "out=$out"

# PR context ("the staging PR") but NO extractable number + a fresh marker for some PR →
# BLOCK (cannot tie the claim to a marker; make the model name the PR).
clear_markers; mark_pass o r 9
mk_transcript "$T" "The staging PR is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: PR context, no number → block" || bad "stop: no-number auto-pass" "out=$out"

# outside-review P1 (both rounds): a verified NUMBERED PR must NOT suppress the block on a
# co-occurring UNNUMBERED PR ready-claim — no matter how the numbered sibling is spelled
# (PR #N / bare #N / URL). Any "PR"/"pull request" word not followed by a number = an
# unverifiable PR → BLOCK, even when every numbered ref has a fresh marker.
# cwd-scoped so the bare/word #7 sibling genuinely PASSES hasFreshPass (marker matches cwd,
# chunk B6) — the block must then come from the UNNUMBERED_PR path, which is what this tests.
clear_markers; mark_pass theowner therepo 7
mk_transcript "$T" "Staging PR #7 is verified and ready. The prod PR is ready to merge."
out=$(stop_decision_cwd "$T" false "$TMP/repo_same")
echo "$out" | grep -q '"decision":"block"' && ok "stop: verified 'PR #7' + unnumbered 'prod PR' → block" || bad "stop: prod-PR false-pass (word)" "out=$out"

# bare-#N spelling of the verified sibling (round-2 residual) → still BLOCK
clear_markers; mark_pass theowner therepo 7
mk_transcript "$T" "#7 verified and ready. The prod PR is ready to merge."
out=$(stop_decision_cwd "$T" false "$TMP/repo_same")
echo "$out" | grep -q '"decision":"block"' && ok "stop: verified bare '#7' + unnumbered 'prod PR' → block" || bad "stop: prod-PR false-pass (#N)" "out=$out"

# URL spelling of the verified sibling (round-2 residual; URL is the house convention) → BLOCK
clear_markers; mark_pass o r 7
mk_transcript "$T" "Verified: https://github.com/o/r/pull/7 all green. The prod PR is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: verified URL sibling + unnumbered 'prod PR' → block" || bad "stop: prod-PR false-pass (URL)" "out=$out"

# ACCEPTED false-block: an unnumbered "PR" word blocks even when it IS the same, verified PR —
# sameness can't be proven without the cross-clause reasoning this redesign forbids, so block
# is the only safe resolution (brief: benign false-blocks accepted). Model avoids it by naming
# the number ("PR #5 is ready: <url>", tested ALLOW elsewhere).
clear_markers; mark_pass theowner therepo 5
mk_transcript "$T" "The staging PR is ready to merge: https://github.com/theowner/therepo/pull/5"
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: unnumbered 'staging PR' word (even w/ verified URL) → block (accepted)" || bad "stop: unnumbered-word not blocked" "out=$out"

# ── readiness-token coverage: each token type, with a PR ref + no marker → BLOCK ───────────
clear_markers
for msg in "PR #9 is shipped." "PR #9 is mergeable now." "PR #9 — all checks green." "PR #9: 0 unresolved threads." "PR #9 LGTM to merge." "PR #9 is good to go."; do
  mk_transcript "$T" "$msg"
  out=$(stop_decision "$T" false)
  echo "$out" | grep -q '"decision":"block"' && ok "token: '$msg' → block" || bad "token: $msg" "out=$out"
done

# ── LOCAL adjacent-negation (the entire cleverness budget) ──────────────────────────────
# A truthful "not ready" report — the sole readiness token is locally negated → ALLOW.
clear_markers
mk_transcript "$T" "PR #9 is not ready to merge; 7 unresolved threads remain."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: negated 'not ready' report → allow" || bad "stop: neg not-ready" "out=$out"

# 'done' in a later sentence is not a token; the only readiness word is negated → ALLOW.
mk_transcript "$T" "PR #9 is not ready: checks are failing. Done investigating for now."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: not-ready + 'done investigating' → allow" || bad "stop: done investigating" "out=$out"

# bare "Finished PR #17. Done." — neither 'finished' nor 'done' is a readiness token → ALLOW
# (block-biased BEHAVIOR CHANGE; old design gated on bare 'done').
clear_markers
mk_transcript "$T" "Finished PR #17. Done."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: 'Finished PR #17. Done.' (no ready token) → allow" || bad "stop: finished/done not a token" "out=$out"

# 'no issues, ready' — a stray negator that a NOUN separates from the token is NOT a local
# negation → the token stays live → BLOCK (guards the char-window false-PASS).
clear_markers
mk_transcript "$T" "PR #9: no issues, ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: 'no issues, ready' (noun breaks negation) → block" || bad "stop: no-issues false-pass" "out=$out"

# ── BEHAVIOR CHANGES accepted by design (brief acceptance): a non-negated readiness token
#    in an otherwise truthful not-ready report now BLOCKs (safe false-block). ───────────────
# "0 unresolved" IS a readiness token → this blocks even though "not ready" is negated.
clear_markers
mk_transcript "$T" "PR #9 is not ready: checks are failing, 0 unresolved review threads."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: not-ready report w/ '0 unresolved' token → block (by design)" || bad "stop: 0-unresolved token" "out=$out"

# MIXED report — no per-PR disposition: "#7 is ready" is live and #9 is referenced w/o a
# marker → BLOCK, even though #9 is declared not-ready and #7 is verified. Accepted safe
# false-block (old design allowed via sentence-scoping).
clear_markers; mark_pass o r 7
mk_transcript "$T" "PR #9 is not ready: checks are failing. PR #7 is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: mixed report (no disposition) → block (safe false-block)" || bad "stop: mixed report" "out=$out"

# intra-sentence "but" mixed polarity → same: no contrast-split, #9 unmarked → BLOCK.
clear_markers; mark_pass o r 7
mk_transcript "$T" "PR #9 is not ready, but PR #7 is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: intra-sentence 'but' mixed → block (no contrast-split)" || bad "stop: intra-sentence mixed" "out=$out"

# FALSE-PASS GUARD: a readiness verb split from its PR ref across sentences still blocks
# (harvest is over the whole message; #17 is referenced and unmarked).
clear_markers
mk_transcript "$T" "Finished PR #17. It is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: cross-sentence claim+ref, unverified → block" || bad "stop: split claim false-pass" "out=$out"

# a ref LIST must require ALL (one verified sibling must not carry the unverified one)
clear_markers; mark_pass o r 7
mk_transcript "$T" "PR #7 and PR #9 are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: ref list, one unverified → block (no false-pass)" || bad "stop: list false-pass" "out=$out"

# ── THE 4 CANONICAL CASES (chunk B4R brief) ─────────────────────────────────────────────
# (1) THE P1 the old parser false-PASSed: un-negated token first, negated later → BLOCK.
clear_markers
mk_transcript "$T" "PR #9 is ready to merge, but the summary for PR #9 is not ready."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "canonical 1: 'ready … but … is not ready' → block (P1 killed)" || bad "canonical 1 P1 false-pass" "out=$out"

# (2) only token is locally negated → ALLOW.
clear_markers
mk_transcript "$T" "PR #9 is not ready to merge. Done."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "canonical 2: 'is not ready to merge. Done.' → allow" || bad "canonical 2 not-ready" "out=$out"

# (3) 'the docs are ready' is un-negated → BLOCK (safe, accepted false-block).
clear_markers
mk_transcript "$T" "PR #9 is not ready, but the docs are ready."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "canonical 3: '…not ready, but the docs are ready' → block (safe false-block)" || bad "canonical 3 docs-ready" "out=$out"

# (4) plural claim, neither marked → BLOCK (both required).
clear_markers
mk_transcript "$T" "PRs #7 and #8 are ready"
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "canonical 4: 'PRs #7 and #8 are ready' (no markers) → block" || bad "canonical 4 plural" "out=$out"

# ── HARVEST variants (absorbs old chunk B4.3) ───────────────────────────────────────────
# singular bare #N
clear_markers
mk_transcript "$T" "Wrapped it up — #9 is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: singular bare '#9' → block" || bad "harvest singular" "out=$out"

# plural list "#7, #8 and #9" — all three required; only #7 marked → BLOCK
clear_markers; mark_pass o r 7
mk_transcript "$T" "PRs #7, #8 and #9 are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: plural list, missing markers → block" || bad "harvest plural list" "out=$out"

# LIST-ELISION (Codex P1): later items with the # ELIDED must still be harvested, so #8 is
# gated even though only #7 is spelled with a #. #7 verified, #8 NOT → BLOCK. Three connectors.
clear_markers; mark_pass o r 7
mk_transcript "$T" "PRs #7 and 8 are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: elided '#7 and 8', #8 unverified → block" || bad "harvest elision and" "out=$out"
clear_markers; mark_pass o r 7
mk_transcript "$T" "PRs #7, 8 and 9 are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: elided '#7, 8 and 9', #8/#9 unverified → block" || bad "harvest elision comma-and" "out=$out"
clear_markers; mark_pass o r 7
mk_transcript "$T" "PRs #7 & 8 are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: elided '#7 & 8', #8 unverified → block" || bad "harvest elision amp" "out=$out"

# same elided list with EVERY listed PR verified (same repo as cwd) → ALLOW (harvest correct,
# no over-block; bare `#N`s scope to the current repo under B6 → markers must match cwd).
clear_markers; mark_pass theowner therepo 7; mark_pass theowner therepo 8; mark_pass theowner therepo 9
mk_transcript "$T" "PRs #7, 8 and 9 are ready to merge."
out=$(stop_decision_cwd "$T" false "$TMP/repo_same")
[ -z "$out" ] && ok "harvest: elided list, ALL verified (same-repo cwd) → allow" || bad "harvest elision all-verified" "out=$out"

# extra connectors (code-review): slash / plus shorthand, #8 unverified → BLOCK
clear_markers; mark_pass o r 7
mk_transcript "$T" "PRs #7/8 are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: '#7/8' slash, #8 unverified → block" || bad "harvest slash" "out=$out"
clear_markers; mark_pass o r 7
mk_transcript "$T" "PRs #7+8 are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: '#7+8' plus, #8 unverified → block" || bad "harvest plus" "out=$out"

# Oxford ", and" (outside-review P1b): #7,#8 verified, #9 NOT → BLOCK (run must not stop at #8)
clear_markers; mark_pass o r 7; mark_pass o r 8
mk_transcript "$T" "PRs #7, 8, and 9 are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: Oxford '#7, 8, and 9', #9 unverified → block" || bad "harvest oxford" "out=$out"

# no-# anchor list (outside-review P1a): bare-word "PRs 7 and 8" — mirrors the bare-word
# singular HARVEST_WORD already gates; #7 verified, #8 NOT → BLOCK.
clear_markers; mark_pass o r 7
mk_transcript "$T" "PRs 7 and 8 are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: no-# word-anchor 'PRs 7 and 8', #8 unverified → block" || bad "harvest word-anchor list" "out=$out"

# spelled-out "pull requests #7 and #8" + a different readiness token ("good to merge")
clear_markers
mk_transcript "$T" "The two pull requests #7 and #8 are good to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: spelled-out 'pull requests #7 and #8' → block" || bad "harvest spelled-out" "out=$out"

# hyphen/whitespace spelling of "pull request" (round-3 P2): an unnumbered "pull-request" word
# must still block; harvest must still pick up a numbered "pull-request #8".
clear_markers
mk_transcript "$T" "The staging pull-request is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: unnumbered 'pull-request' (hyphen) → block" || bad "harvest hyphen unnumbered" "out=$out"
clear_markers; mark_pass o r 7
mk_transcript "$T" "pull-request #7 and pull-request #8 are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: numbered 'pull-request #8' (hyphen), #8 unverified → block" || bad "harvest hyphen numbered" "out=$out"

# anaphoric "Both PRs" — numbers named earlier in the SAME message; neither marked → BLOCK
clear_markers
mk_transcript "$T" "I opened #7 and #8 this morning. Both PRs are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: anaphoric 'Both PRs' (earlier #7 #8) → block" || bad "harvest anaphoric" "out=$out"

# same anaphoric claim with BOTH earlier-named PRs verified → still BLOCK: "Both PRs" is an
# unnumbered PR word, and we can't prove it points only at the two verified numbers (accepted
# false-block; the model avoids it by writing "#7 and #8 are ready" — see the numbered
# "PR #7 and PR #9 both verified → allow" case, which stays ALLOW).
clear_markers; mark_pass o r 7; mark_pass o r 8
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "harvest: anaphoric 'Both PRs', both verified → block (accepted false-block)" || bad "harvest anaphoric verified" "out=$out"

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

# A REAL merged-orphan needs the base to EXIST on the remote (so the fetch SUCCEEDS) yet
# NOT contain HEAD. Build an independent 'master' on the bare (orphan root — none of
# feature/w1-x's history), so the merged PR's base fetch succeeds and is-ancestor is
# false → 🚨 orphan, exit 2. (An UNfetchable base is a DIFFERENT case — asserted next.)
git -C "$FX" checkout -q --orphan master-seed
git -C "$FX" rm -rfq . >/dev/null 2>&1 || true
echo m > "$FX/m"; git -C "$FX" add -A; $GITC -C "$FX" commit -qm master-root
git -C "$FX" push -q origin master-seed:master 2>/dev/null
git -C "$FX" checkout -qf feature/w1-x
GH_MODE=merged; out=$(feed 'git push origin feature/w1-x')
{ echo "$out" | grep -q 'rc=2' && echo "$out" | grep -q 'ORPHANED FIX'; } && ok "cfl: push merged-PR excl HEAD → orphan(2)" || bad "cfl: merged orphan" "$out"

# MERGED PR but the base ref is UNFETCHABLE (timeout/auth/deleted base) → we CANNOT tell
# whether HEAD landed, so fail-open silent(0) — never a false ORPHANED FIX (Codex P2,
# mirrors the gh-lookup-fail guard). Base 'ghost-base' isn't on the bare → fetch fails.
GH_MODE=merged_nofetch; out=$(feed 'git push origin feature/w1-x')
{ echo "$out" | grep -q 'rc=0' && [ "$(echo "$out" | grep -c 'ORPHANED FIX')" = 0 ]; } && ok "cfl: merged base unfetchable → silent(0)" || bad "cfl: merged fetch-fail false orphan" "$out"

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
