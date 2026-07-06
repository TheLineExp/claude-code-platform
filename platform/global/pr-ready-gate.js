#!/usr/bin/env node
/**
 * pr-ready-gate.js — makes shipit Step 5b's "PR-Ready gate" a REAL control, not prose.
 *
 * The audit (Theme E, E3) found the PR-Ready gate was prose-only: "never report a PR
 * ready without verifying LIVE state" was skipped ~25× because nothing enforced it —
 * the same control class that already failed elsewhere. This file closes it with two
 * modes sharing ONE marker convention:
 *
 *   VERIFY MODE   `node pr-ready-gate.js verify <owner/repo> <pr#>`
 *     Runs `gh pr checks` + the unresolved-review-thread GraphQL count. Only if checks
 *     are green AND unresolved threads == 0 does it write a fresh PASS marker. This is
 *     what shipit Step 5b runs immediately before claiming a PR is ready.
 *
 *   STOP-HOOK MODE   (no args; Stop event JSON on stdin)
 *     Reads the final assistant message. If it makes a PR-readiness claim
 *     (ready / done / shipped, co-occurring with a PR reference) but there is NO fresh
 *     PASS marker for that PR, it BLOCKS the stop and tells the model to run verify
 *     mode first. A stale or absent marker can no longer pass silently.
 *
 * Marker: <tmp>/claude-pr-ready/<owner>_<repo>_<pr>.json  {verdict, ts, ...}. Fresh =
 * written within FRESH_MS. FAILS OPEN on every error and never loops (respects
 * stop_hook_active) — it can annoy, but it can never wedge a session.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const FRESH_MS = 20 * 60 * 1000; // a marker older than 20 min is stale — re-verify
const MARKER_DIR = path.join(os.tmpdir(), 'claude-pr-ready');

function markerPath(owner, repo, pr) {
  return path.join(MARKER_DIR, `${sanitize(owner)}_${sanitize(repo)}_${sanitize(String(pr))}.json`);
}
function sanitize(s) { return String(s).replace(/[^A-Za-z0-9_.-]/g, '_').slice(0, 80); }

// ── VERIFY MODE ───────────────────────────────────────────────────────────────
function verify(argv) {
  const target = argv[0] || '';           // "owner/repo"
  const pr = String(argv[1] || '').replace(/[^0-9]/g, '');
  const m = target.match(/^([^/]+)\/([^/]+)$/);
  if (!m || !pr) {
    console.error('usage: pr-ready-gate.js verify <owner/repo> <pr#>');
    process.exit(2);
  }
  const owner = m[1], repo = m[2];

  // 1. Checks: `gh pr checks` exits non-zero if any check is failing/pending. "No checks
  //    reported" (repos without CI) is not a failure — treat as green.
  let checksGreen = true, checksNote = '';
  try {
    const out = run('gh', ['pr', 'checks', pr, '--repo', `${owner}/${repo}`]);
    checksNote = firstLine(out) || 'all green';
  } catch (e) {
    const out = String((e && (e.stdout || e.stderr)) || '');
    if (/no checks reported|no checks on/i.test(out)) { checksNote = 'no checks reported'; }
    else { checksGreen = false; checksNote = firstLine(out) || 'checks failing/pending'; }
  }

  // 2. Unresolved review threads (Codex comments live here) — the Step 5b GraphQL count.
  //    PAGINATED: `reviewThreads(first:100)` alone misses an unresolved thread on a later
  //    page of a Codex-heavy PR → false PASS. The query carries pageInfo + $endCursor and
  //    `--paginate` walks every page; `--jq` emits one count per page, which we sum (Codex).
  let unresolved = null;
  try {
    const q = 'query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100,after:$endCursor){nodes{isResolved} pageInfo{hasNextPage endCursor}}}}}';
    const out = run('gh', ['api', 'graphql', '--paginate', '-f', `query=${q}`,
      '-f', `owner=${owner}`, '-f', `repo=${repo}`, '-F', `pr=${pr}`,
      '--jq', '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved==false)]|length']);
    const counts = out.split('\n').map(s => parseInt(s.trim(), 10)).filter(n => !Number.isNaN(n));
    unresolved = counts.length ? counts.reduce((a, b) => a + b, 0) : null;
  } catch (e) { unresolved = null; }

  const pass = checksGreen && unresolved === 0;
  const marker = {
    owner, repo, pr: Number(pr),
    verdict: pass ? 'PASS' : 'FAIL',
    checksGreen, checksNote, unresolved,
    ts: Date.now(),
  };
  try { fs.mkdirSync(MARKER_DIR, { recursive: true }); fs.writeFileSync(markerPath(owner, repo, pr), JSON.stringify(marker)); } catch (e) { /* ignore */ }
  pruneOld();

  if (pass) {
    console.log(`PR-READY VERIFIED: ${owner}/${repo}#${pr} — checks ${checksNote}, 0 unresolved threads. Marker written (valid ${FRESH_MS / 60000} min).`);
    process.exit(0);
  } else {
    const why = !checksGreen ? `checks NOT green (${checksNote})` : `${unresolved == null ? 'unknown' : unresolved} unresolved review thread(s)`;
    console.error(`PR-READY BLOCKED: ${owner}/${repo}#${pr} — ${why}. Do NOT report ready; fix, push, and re-verify.`);
    process.exit(1);
  }
}

// ── STOP-HOOK MODE ──────────────────────────────────────────────────────────────
function stopHook() {
  let input;
  try { input = JSON.parse(fs.readFileSync(0, 'utf8') || '{}'); } catch { return; }

  // Never loop: if this stop is already a continuation forced by a stop hook, let it pass.
  if (input.stop_hook_active) return;

  const transcript = input.transcript_path;
  if (!transcript || !fs.existsSync(transcript)) return;

  const text = lastAssistantText(transcript);
  if (!text) return;

  // A "claim" = a readiness VERB (ready / done / shipped / good-to-merge). Evidence fragments
  // ("all checks green", "0 unresolved") are NOT claims — they appear verbatim in BLOCKED
  // reports, so gating on them false-blocked truthful failure reports. "done" is tightened to
  // a COMPLETION sense: "done <gerund>" / "done for now" / "done with …" are ACTIVITIES, not a
  // PR-done claim (Codex: a bare "Done investigating for now" in a blocked report).
  const readinessRe = /(ready to (merge|ship)|good to (merge|go|ship)|safe to (merge|ship)|(is|are|now)\s+ready\b|\bdone\b(?!\s+(?:\w+ing\b|for\s+(?:now|today|the\s+day)|with\b))|✅[^\n]*\b(ready|done|shipped)\b|\bshipped\b)/i;
  const prContextRe = /(github\.com\/[^\s)]+\/pull\/\d+|\bPR\s*#?\d+|\bpull request\b|staging PR|production PR|prod PR)/i;

  // Neutralize a NEGATED claim ("PR #N is not ready to merge") so a truthful blocked-state
  // report is not gated; a mixed "#9 not ready but #7 is ready to merge" keeps the positive #7.
  const deNegate = (s) => s.replace(
    /\b(not|no longer|never|isn'?t|aren'?t|won'?t|can'?t|cannot|wasn'?t|weren'?t)\s+(?:(?:yet|fully|quite|totally|entirely|completely|necessarily|really|actually)\s+){0,3}((safe|good|ready|able|clear)\s+to\s+\w+|ready\b|done\b|shipped\b|merged\b|good\s+to\s+(go|merge|ship))/gi,
    ' ');

  // STRONG PR refs only — a `/pull/N` URL (carries its repo) or an explicit `PR #N`. A bare
  // `#N` is not harvested (it scoops issue refs / "closes #7" tails). A `/owner/repo/pull/N`
  // URL requires a SAME-repo marker (numbers collide across the 3 fleet repos, Codex P1); a
  // bare `PR #N` matches on number alone.
  const harvest = (s) => {
    const refs = [];
    for (const mm of s.matchAll(/github\.com\/([^/\s]+)\/([^/\s]+)\/pull\/(\d+)/gi)) refs.push({ repo: `${mm[1]}/${mm[2]}`, pr: mm[3] });
    for (const mm of s.matchAll(/\bPR\s*#?(\d+)/gi)) refs.push({ repo: null, pr: mm[1] });
    return refs;
  };

  // SENTENCE-SCOPE the association: a readiness verb and a PR ref bind into a claim only when
  // they share the SAME sentence. This stops cross-sentence bleeding — a bare "done" in one
  // sentence no longer attaches to a PR in another (Codex: "…not ready. Done investigating."),
  // and a mixed report no longer demands a marker for the PR it says is NOT ready (Codex:
  // "#9 is not ready … #7 is ready to merge"). Split on sentence enders FOLLOWED BY whitespace
  // (so a '.' inside a URL never splits) or newlines.
  const required = [];               // refs a claim explicitly names in its own sentence
  let unassociatedClaim = false;     // a claim verb whose own sentence names no PR
  for (const s of text.split(/[.!?;]+\s+|[\n\r]+/)) {
    if (!readinessRe.test(deNegate(s))) continue;
    const refs = harvest(s);
    if (refs.length) required.push(...refs);
    else unassociatedClaim = true;
  }

  if (!required.length && !unassociatedClaim) return;   // no readiness claim at all

  // A claim whose sentence named no PR: fall back to EVERY PR ref in the message and require
  // each verified — biased to BLOCK, so a real "ready to merge" split from its PR ref across
  // sentences cannot slip. If no extractable PR but PR CONTEXT is present ("the staging PR is
  // ready"), block to force naming. No PR context at all → the verb was unrelated prose.
  if (unassociatedClaim) {
    const all = harvest(text);
    if (all.length) required.push(...all);
    else if (prContextRe.test(text)) { blockReady(); return; }
    else return;
  }

  if (hasFreshPass(required)) return;   // every claimed PR has its own fresh PASS marker
  blockReady();

  function blockReady() {
    const reason =
      'PR-READY GATE (shipit Step 5b) — you are about to report a PR ready/done/shipped, ' +
      'but there is no FRESH verification marker for it. A stale "ready" claim is a defect. ' +
      'Run: `node ~/.claude/hooks/pr-ready-gate.js verify <owner/repo> <pr#>` — it checks ' +
      '`gh pr checks` + the unresolved-review-thread count and only passes on "green + 0 ' +
      'unresolved". If it BLOCKS, fix the failing checks / unresolved threads, push, and ' +
      're-verify. Only report ready after it prints PR-READY VERIFIED.';
    process.stdout.write(JSON.stringify({ decision: 'block', reason }));
  }
}

// EVERY named PR ref must be satisfied by its OWN fresh PASS marker. A claim naming
// several PRs ("#7 and #9 are both ready") must not ride through on one sibling's
// marker — the staging-verified / prod-unverified multi-PR risk (outside-review P2.1).
// A repo-qualified ref (from a /pull/ URL) requires a SAME-REPO marker — a cross-repo
// #N collision must not satisfy it (Codex P1). A bare ref matches on number alone.
// If the claim carried PR context but no extractable ref ("the staging PR is ready"),
// prRefs is empty → block and make the model name + verify the PR (its P2 pair).
function hasFreshPass(prRefs) {
  if (!prRefs.length) return false;
  let markers;
  try { markers = fs.readdirSync(MARKER_DIR); } catch { return false; }
  const now = Date.now();
  const fresh = [];   // {repo:'owner/repo'|null, pr:'N'}
  for (const f of markers) {
    if (!f.endsWith('.json')) continue;
    let mk;
    try { mk = JSON.parse(fs.readFileSync(path.join(MARKER_DIR, f), 'utf8')); } catch { continue; }
    if (mk.verdict !== 'PASS') continue;
    if (now - (mk.ts || 0) > FRESH_MS) continue;
    fresh.push({ repo: (mk.owner && mk.repo) ? `${mk.owner}/${mk.repo}` : null, pr: String(mk.pr) });
  }
  for (const ref of prRefs) {
    const ok = fresh.some(m => m.pr === ref.pr && (ref.repo == null || m.repo === ref.repo));
    if (!ok) return false;   // any un-verified (or wrong-repo) named PR blocks
  }
  return true;
}

// ── INVALIDATE MODE ─────────────────────────────────────────────────────────────
// `node pr-ready-gate.js invalidate <owner/repo> <pr#>` — delete a PR's PASS marker.
// check-fix-landed.sh calls this on every push: a push moves the PR head, which can
// reset checks to pending/failing, so a marker written before that push must NOT keep
// certifying the PR "ready" for the rest of its 20-min window (Codex P1: head-SHA
// staleness). Re-running verify after the push re-writes a fresh marker. Best-effort.
function invalidate(argv) {
  const m = String(argv[0] || '').match(/^([^/]+)\/([^/]+)$/);
  const pr = String(argv[1] || '').replace(/[^0-9]/g, '');
  if (!m || !pr) return;
  try { fs.unlinkSync(markerPath(m[1], m[2], pr)); } catch { /* absent → nothing to invalidate */ }
}

function lastAssistantText(transcript) {
  let data;
  try { data = fs.readFileSync(transcript, 'utf8'); } catch { return ''; }
  const lines = data.split('\n');
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i];
    if (!line.includes('"type":"assistant"')) continue;
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (o.type !== 'assistant') continue;
    const content = (o.message && o.message.content) || [];
    const text = content.filter(c => c && c.type === 'text').map(c => c.text).join('\n').trim();
    if (text) return text; // last TEXT-bearing assistant turn — skip trailing pure
                           // tool-call turns whose text is empty (outside-review P2)
  }
  return '';
}

// ── shared ──────────────────────────────────────────────────────────────────────
function run(cmd, args) {
  return execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000 });
}
function firstLine(s) { return String(s || '').split('\n').map(x => x.trim()).filter(Boolean)[0] || ''; }
function pruneOld() {
  try {
    const cutoff = Date.now() - 24 * 3600 * 1000;
    for (const f of fs.readdirSync(MARKER_DIR)) {
      const p = path.join(MARKER_DIR, f);
      try { if (fs.statSync(p).mtimeMs < cutoff) fs.unlinkSync(p); } catch { /* best effort */ }
    }
  } catch { /* best effort */ }
}

// ── entry ─────────────────────────────────────────────────────────────────────
try {
  const argv = process.argv.slice(2);
  if (argv[0] === 'verify') verify(argv.slice(1));
  else if (argv[0] === 'invalidate') invalidate(argv.slice(1));
  else stopHook();
} catch { /* fail open — never break a session */ }
process.exit(0);
