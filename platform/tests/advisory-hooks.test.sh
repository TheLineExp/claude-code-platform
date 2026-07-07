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

# ── SENTENCE-SCOPING + negation (Codex rounds on the NL readiness matcher) ──────────────
# A truthful "not ready" report must NOT block (thread 7).
clear_markers
mk_transcript "$T" "PR #9 is not ready to merge; 7 unresolved threads remain."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: negated 'not ready' report → allow" || bad "stop: neg not-ready" "out=$out"

# Evidence fragments ("0 unresolved") inside a BLOCKED report are not a claim (threads A + rd4).
mk_transcript "$T" "PR #9 is not ready: checks are failing, 0 unresolved review threads."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: blocked report w/ 0-unresolved evidence → allow" || bad "stop: evidence-in-blocked" "out=$out"

# A bare 'done' in a DIFFERENT sentence from the (not-ready) PR must NOT attach to it (thread X).
mk_transcript "$T" "PR #9 is not ready: checks are failing. Done investigating for now."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: cross-sentence 'done investigating' → allow" || bad "stop: cross-sentence done" "out=$out"

# MIXED report — #9 not ready, #7 ready+VERIFIED → allow; must NOT require #9's marker (thread Y).
clear_markers; mark_pass o r 7
mk_transcript "$T" "PR #9 is not ready: checks are failing. PR #7 is ready to merge."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: mixed report, only the ready PR required (verified) → allow" || bad "stop: mixed requires not-ready PR" "out=$out"

# Same mixed report but the ready PR is UNVERIFIED → block (on #7 only).
clear_markers
mk_transcript "$T" "PR #9 is not ready: checks are failing. PR #7 is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: mixed report, ready PR unverified → block" || bad "stop: mixed unverified should block" "out=$out"

# FALSE-PASS GUARD: a readiness verb split from its PR ref across sentences must still block
# (the unassociated-claim fallback requires every named PR verified — safe direction).
clear_markers
mk_transcript "$T" "Finished PR #17. It is ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: cross-sentence claim+ref, unverified → block" || bad "stop: split claim false-pass" "out=$out"

# 'done <gerund>' is an ACTIVITY, not a completion claim, even with a same-sentence PR (thread X class).
clear_markers
mk_transcript "$T" "Done reviewing PR #9 for now."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: 'done reviewing PR #9' (activity) → allow" || bad "stop: done-gerund same-sentence" "out=$out"

# thread Q: a bare completion 'Done.' after a NEGATED PR status must not demand that PR's marker.
clear_markers
mk_transcript "$T" "PR #9 is not ready: checks are failing. Done."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: bare 'Done.' after not-ready PR → allow (sign-off)" || bad "stop: bare done sign-off" "out=$out"

# guard: an unassociated claim with a NON-negated PR ref still requires it (no false-pass).
clear_markers
mk_transcript "$T" "Finished PR #17. Done."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: unassociated claim, live PR unverified → block" || bad "stop: unassociated live PR" "out=$out"

# intra-sentence MIXED polarity ("#9 not ready, but #7 ready") — split on the contrast
# conjunction so only the ready PR (#7, verified) is required, not the not-ready #9.
clear_markers; mark_pass o r 7
mk_transcript "$T" "PR #9 is not ready, but PR #7 is ready to merge."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: intra-sentence mixed (but), ready PR verified → allow" || bad "stop: intra-sentence mixed" "out=$out"
# a ref LIST must still require ALL (contrast-split must not break lists → no false-pass)
clear_markers; mark_pass o r 7
mk_transcript "$T" "PR #7 and PR #9 are ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: ref list, one unverified → block (no false-pass)" || bad "stop: list false-pass" "out=$out"

# B4.2 — CONTRAST-SPLIT PRONOUN CO-REFERENCE (the #18 false-PASS hole).
# The ready clause after "but" uses a PRONOUN ("it") instead of repeating the PR number, and the
# first fragment tagged #9 notReady. Pre-fix: the split dropped the PR association and the
# notReady tag suppressed the claim → NO block → false PASS. The trailing pronoun must resolve to
# #9 and the FINAL disposition ("ready") must require a fresh marker → BLOCK (no marker present).
clear_markers
mk_transcript "$T" "PR #9 is not ready, but it is now ready to merge."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: contrast-split pronoun 'it is now ready' (final=ready), no marker → block" || bad "stop: B4.2 contrast pronoun false-pass" "out=$out"

# INVERSE — the final disposition after the contrast is NOT ready (gapped predicate "it is not
# [ready]"). This is an accurate not-ready report and must NOT block (truthful blocked-state).
clear_markers
mk_transcript "$T" "PR #9 is ready, but it is not."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: contrast-split pronoun 'it is not' (final=not-ready) → allow" || bad "stop: B4.2 inverse over-block" "out=$out"

# B4.2 SAFETY GUARD (review-fix): the reversal must fire ONLY on an ELIDED readiness negation.
# A contrast/negation about a NON-readiness predicate ("not deployed/merged/done yet", "not ready
# for prod") must NOT downgrade a genuine ready-claim — else the pronoun co-reference would open a
# NEW false-PASS (a real "ready to merge" claim slipping past ungated). All of these must BLOCK.
clear_markers
mk_transcript "$T" "PR #9 is ready to merge, but it is not deployed yet."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: 'ready…but it is not deployed yet' (non-readiness neg) → block" || bad "stop: non-readiness neg false-pass" "out=$out"

clear_markers
mk_transcript "$T" "PR #9 is ready to merge. It is not done yet."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: cross-sentence 'It is not done yet' → block" || bad "stop: done-yet false-pass" "out=$out"

clear_markers
mk_transcript "$T" "PR #9 is ready to ship, but it is not ready for prod."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: 'ready…but it is not ready for prod' → block" || bad "stop: ready-for-prod false-pass" "out=$out"

clear_markers
mk_transcript "$T" "PR #9 is ready to merge, but it is not merged yet."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: 'ready…but it is not merged yet' → block" || bad "stop: merged-yet false-pass" "out=$out"

# and the multi-PR widening: one trailing non-readiness negation must not clear a whole ready list.
clear_markers
mk_transcript "$T" "PR #7 and PR #8 are ready to merge, but it is not done deploying."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: ready list + trailing non-readiness neg → block" || bad "stop: list-wide false-pass" "out=$out"

# B4.2 REFERENT-BLEED GUARD (review-fix rd2): the ELIDED-negation reversal must resolve ONLY a
# single PR named in the SAME sentence. A pronoun in a LATER sentence (whose real antecedent is an
# intervening non-PR noun) must NOT flip a genuinely-ready PR from an earlier sentence, and a list
# must never be cleared by one singular pronoun. All of these must BLOCK (unverified ready-claim).
clear_markers
mk_transcript "$T" "PR #9 is ready to merge. The prod release will follow but it is not ready."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: cross-sentence pronoun bleed (non-PR antecedent) → block" || bad "stop: referent bleed false-pass" "out=$out"

clear_markers
mk_transcript "$T" "PR #9 is ready to merge. I also checked the config, but it is not."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: cross-sentence bare 'it is not' → block" || bad "stop: cross-sentence elided bleed" "out=$out"

clear_markers
mk_transcript "$T" "PR #7 and PR #8 are ready to merge, but it is not."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: singular 'it is not' must not clear a ready LIST → block" || bad "stop: list cleared by pronoun" "out=$out"

clear_markers
mk_transcript "$T" "PR #9 is ready to merge. The prod PR is separate and that is not ready."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: cross-sentence 'that is not ready' bleed → block" || bad "stop: that-pronoun bleed" "out=$out"

# B4.2 LIFECYCLE-STATUS GUARD (review-fix rd3): the reversal must fire only on a READINESS
# negation, NOT on a lifecycle-status negation. "not merged/shipped/deployed yet" is the canonical
# state of a ready-to-merge PR, not a retraction of readiness — an explicit "PR #9 is not merged
# yet" alongside a genuine ready-claim must NOT clear it. All of these must BLOCK.
clear_markers
mk_transcript "$T" "PR #9 is ready to merge, but PR #9 is not merged yet."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: 'ready…but PR #9 is not merged yet' (lifecycle, not readiness) → block" || bad "stop: not-merged false-pass" "out=$out"

clear_markers
mk_transcript "$T" "PR #9 is ready to merge. PR #9 is not shipped yet."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: cross-sentence 'PR #9 is not shipped yet' → block" || bad "stop: not-shipped false-pass" "out=$out"

# B4.2 INTERROGATIVE GUARD: a rhetorical tag-question ("…but is it not?") is doubt, not a not-ready
# assertion, and must not clear a genuine ready-claim → block.
clear_markers
mk_transcript "$T" "PR #9 is ready to merge, but is it not?"
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: rhetorical 'but is it not?' → block" || bad "stop: interrogative false-pass" "out=$out"

# B4.2 ZERO-ANAPHOR GUARD (review-fix rd4): the same B4.2 hole with the pronoun ELIDED entirely —
# a subjectless positive clause after a contrast ("…but is ready to merge now") must resolve to the
# single same-sentence PR (final disposition = ready) and require a marker → block.
clear_markers
mk_transcript "$T" "PR #9 is not ready but is ready to merge now."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: zero-anaphor 'not ready but is ready to merge now' → block" || bad "stop: zero-anaphor false-pass" "out=$out"

# but a later positive clause with its OWN subject noun must NOT be co-referenced to the PR (allow).
clear_markers
mk_transcript "$T" "PR #9 is not ready. The docs are ready."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: cross-sentence own-subject 'The docs are ready' → allow" || bad "stop: own-subject over-block" "out=$out"

# B4.2 SCOPED-READINESS GUARD (review-fix rd5): a SCOPED readiness negation ("not ready FOR prod",
# "not ready TO promote") is a different readiness than "ready to merge" and must NOT retract a
# genuine merge-ready claim — the staging→prod flow. All of these must BLOCK.
clear_markers
mk_transcript "$T" "PR #9 is ready to merge to staging. PR #9 is not ready for prod yet."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: 'ready to merge…not ready for prod yet' → block" || bad "stop: ready-for-prod scoped false-pass" "out=$out"

clear_markers
mk_transcript "$T" "PR #9 is ready to merge, but PR #9 is not ready for prod."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: 'ready to merge, but not ready for prod' → block" || bad "stop: ready-for-prod contrast false-pass" "out=$out"

clear_markers
mk_transcript "$T" "PR #9 is ready to merge. PR #9 is not ready to promote."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: 'ready to merge…not ready to promote' → block" || bad "stop: ready-to-promote scoped false-pass" "out=$out"

# and the genuine merge/ship negations must STILL reverse (truthful not-ready reports → allow).
clear_markers
mk_transcript "$T" "PR #9 is not ready to merge yet; still finishing review."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: genuine 'not ready to merge' still reverses → allow" || bad "stop: not-ready-to-merge over-block" "out=$out"

# B4.2 COPULA GUARD (review-fix rd6): the elided reversal is a COPULA negation ("it is not
# [ready]"). An auxiliary/do-support negation ("does/will/did/has/should not") negates some other
# verb, not the readiness copula, and must NOT retract a genuine ready-claim. All of these BLOCK.
clear_markers
mk_transcript "$T" "PR #9 is ready to merge, but it does not."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: aux-negation 'but it does not' → block" || bad "stop: does-not false-pass" "out=$out"

clear_markers
mk_transcript "$T" "PR #9 is ready to merge, but it will not."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: aux-negation 'but it will not' → block" || bad "stop: will-not false-pass" "out=$out"

clear_markers
mk_transcript "$T" "PR #9 is ready to merge. I double-checked that PR #9 does not break the build, and it does not."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: opposite-polarity 'does not break … and it does not' → block" || bad "stop: does-not-break false-pass" "out=$out"

# copula reversal still works (spec inverse + contracted form).
clear_markers
mk_transcript "$T" "PR #9 is ready, but it isn't."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: contracted copula 'but it isn't' → allow" || bad "stop: isnt-copula over-block" "out=$out"

# B4.2 MULTI-REF GUARD (review-fix rd7): a negation clause naming MORE THAN ONE PR is ambiguous
# about which it retracts and must NOT blanket-flip them all — else a genuine earlier ready-claim
# for a co-mentioned PR gets clobbered by last-write-wins. These must BLOCK (#7 was called ready).
clear_markers
mk_transcript "$T" "PR #7 is ready to merge. Note that PR #9 and PR #7 are not ready."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: multi-ref 'PR #9 and PR #7 are not ready' must not clear ready #7 → block" || bad "stop: multi-ref blanket-flip false-pass" "out=$out"

clear_markers
mk_transcript "$T" "PR #7 is ready to merge. PR #9 and PR #7 are not."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: multi-ref elided 'PR #9 and PR #7 are not' → block" || bad "stop: multi-ref elided false-pass" "out=$out"

# but a truthful multi-ref not-ready report with NO competing ready-claim still allows.
clear_markers
mk_transcript "$T" "PR #9 and PR #7 are not ready to merge; both have open threads."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: truthful multi-ref not-ready report → allow" || bad "stop: multi-ref truthful over-block" "out=$out"

# B4.2 SCOPED-EXPLICIT GUARD (review-fix rd8): even a SAME-PR explicit negation of a DIFFERENT
# readiness scope ("ready to merge" claimed, "not ready to ship" noted) must not retract the
# merge-ready claim → block. Only an unscoped "not ready" reverses.
clear_markers
mk_transcript "$T" "PR #9 is ready to merge, but PR #9 is not ready to ship."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: same-PR scoped 'not ready to ship' must not clear merge-ready → block" || bad "stop: scoped-explicit false-pass" "out=$out"

# B4.2 DETERMINER GUARD (review-fix rd9): the elided-reversal pronoun must be the copula SUBJECT
# ("it is not"), NOT a determiner before another noun ("that COMMIT is not" refers to a non-PR
# thing). A contrast clause about a different noun must not retract the PR's merge-ready claim.
clear_markers
mk_transcript "$T" "PR #9 is ready to merge, but that commit is not."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: determiner 'that commit is not' must not clear #9 → block" || bad "stop: determiner-that false-pass" "out=$out"

clear_markers
mk_transcript "$T" "PR #9 is ready to merge, however that regression test is not."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: determiner 'that test is not' (however) → block" || bad "stop: determiner-however false-pass" "out=$out"

# but a genuine pronoun-subject reversal ("that is not") still allows (spec-inverse sibling).
clear_markers
mk_transcript "$T" "PR #9 is ready, but that is not."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: pronoun-subject 'that is not' → allow" || bad "stop: pronoun-subject over-block" "out=$out"

# B4.2 SCOPED-SIGNOFF GUARD (review-fix rd10, Codex :180): a truthful scoped not-ready report
# ("PR #9 is not ready to merge") followed by a bare sign-off ("Done.") must NOT be blocked — the
# scoped negation stays OFF the sign-off requirement (notReadyMention) without flipping disposition.
clear_markers
mk_transcript "$T" "PR #9 is not ready to merge. Done."
out=$(stop_decision "$T" false)
[ -z "$out" ] && ok "stop: scoped 'not ready to merge. Done.' sign-off → allow" || bad "stop: scoped-signoff over-block" "out=$out"

# but a LATER genuine ready-claim for that same PR still wins → block (sign-off exclusion must not
# override a final ready disposition).
clear_markers
mk_transcript "$T" "PR #9 is not ready to merge. PR #9 is ready to merge now. Done."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: scoped not-ready then genuine ready → block" || bad "stop: scoped-signoff swallowed a real ready" "out=$out"

# and the scoped exclusion must NOT reintroduce the rd8 clobber (same-PR different-scope, no sign-off).
clear_markers
mk_transcript "$T" "PR #9 is ready to merge, but PR #9 is not ready to ship."
out=$(stop_decision "$T" false)
echo "$out" | grep -q '"decision":"block"' && ok "stop: scoped exclusion preserves rd8 (merge-ready stands) → block" || bad "stop: rd8 regression" "out=$out"

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
