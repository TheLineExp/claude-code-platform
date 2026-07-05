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
  let unresolved = null;
  try {
    const q = 'query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100){nodes{isResolved}}}}}';
    const out = run('gh', ['api', 'graphql', '-f', `query=${q}`,
      '-f', `owner=${owner}`, '-f', `repo=${repo}`, '-F', `pr=${pr}`,
      '--jq', '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved==false)]|length']);
    unresolved = parseInt(firstLine(out), 10);
    if (Number.isNaN(unresolved)) unresolved = null;
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

  // Fire only on a genuine PR-readiness CLAIM: a readiness state AND a PR reference must
  // co-occur — so ordinary "done" in unrelated prose never trips it.
  const readinessRe = /(ready to (merge|ship)|good to (merge|go|ship)|safe to (merge|ship)|(is|are|now)\s+ready\b|is done\b|✅[^\n]*\b(ready|done|shipped)\b|\bshipped\b|all checks?\s+(are\s+)?green|0 unresolved)/i;
  const prContextRe = /(github\.com\/[^\s)]+\/pull\/\d+|\bPR\s*#?\d+|\bpull request\b|staging PR|production PR|prod PR)/i;
  if (!readinessRe.test(text) || !prContextRe.test(text)) return;

  // Which PRs does the claim name? Only STRONG references — a `/pull/N` URL or an
  // explicit `PR #N`. A bare `#N` is NOT harvested: it scoops issue refs and
  // "closes #7" tails, and a fresh marker for that unrelated number would then
  // falsely satisfy the claim (outside-review P1 — the multi-PR shipit flow where
  // staging #7 was verified but prod #9 is the actual claim).
  const prNums = new Set();
  for (const mm of text.matchAll(/\/pull\/(\d+)/g)) prNums.add(mm[1]);
  for (const mm of text.matchAll(/\bPR\s*#?(\d+)/gi)) prNums.add(mm[1]);

  if (hasFreshPass(prNums)) return; // verified — allow the claim

  const reason =
    'PR-READY GATE (shipit Step 5b) — you are about to report a PR ready/done/shipped, ' +
    'but there is no FRESH verification marker for it. A stale "ready" claim is a defect. ' +
    'Run: `node ~/.claude/hooks/pr-ready-gate.js verify <owner/repo> <pr#>` — it checks ' +
    '`gh pr checks` + the unresolved-review-thread count and only passes on "green + 0 ' +
    'unresolved". If it BLOCKS, fix the failing checks / unresolved threads, push, and ' +
    're-verify. Only report ready after it prints PR-READY VERIFIED.';
  process.stdout.write(JSON.stringify({ decision: 'block', reason }));
}

// A fresh PASS marker for at least one SPECIFICALLY-named PR. If the claim carried
// PR context but no extractable number ("the staging PR is ready"), we cannot tie it
// to a marker — block and make the model name the PR + verify, rather than pass on an
// unrelated fresh marker (outside-review P2 — pairs with the P1 above).
function hasFreshPass(prNums) {
  if (prNums.size === 0) return false;
  let markers;
  try { markers = fs.readdirSync(MARKER_DIR); } catch { return false; }
  const now = Date.now();
  for (const f of markers) {
    if (!f.endsWith('.json')) continue;
    let mk;
    try { mk = JSON.parse(fs.readFileSync(path.join(MARKER_DIR, f), 'utf8')); } catch { continue; }
    if (mk.verdict !== 'PASS') continue;
    if (now - (mk.ts || 0) > FRESH_MS) continue;
    if (prNums.has(String(mk.pr))) return true;
  }
  return false;
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
  else stopHook();
} catch { /* fail open — never break a session */ }
process.exit(0);
