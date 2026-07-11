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
 *   STOP-HOOK MODE   (no args; Stop event JSON on stdin) — BLOCK-BIASED (chunk B4R)
 *     Reads the final assistant message. It BLOCKS the stop when the message names a PR
 *     and carries a non-negated readiness token for which there is no fresh PASS marker.
 *     The decision is deliberately dumb — it NEVER reasons across clauses (no contrast
 *     split, no negation scoping, no pronoun/subject co-reference). See stopHook() for
 *     why that dumbness is the whole point: the coreference bug family cannot exist.
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

// ── STOP-HOOK MODE (block-biased — chunk B4R redesign) ────────────────────────────
// Replaces the old per-PR disposition parser (contrast-split + negation-scoping +
// pronoun/subject co-reference) — an unbounded false-PASS source across 12 review rounds.
// This never binds a token to a PR and never reasons across a clause. Three flat checks:
// a LIVE readiness token (hasLiveReadyToken) + a referenced PR (harvest) + a missing fresh
// marker (hasFreshPass — bare `#N` scoped to the current repo, chunk B6) → BLOCK. No
// clause-crossing → the coreference/contrast/
// subject bug family cannot exist. Price: rare, SAFE false-blocks (accepted for an internal
// dev tool where a missed false-PASS is the only real hazard; a false-block costs one
// loop-safe turn). See the PR body for the full design rationale.
function stopHook() {
  let input;
  try { input = JSON.parse(fs.readFileSync(0, 'utf8') || '{}'); } catch { return; }

  // Never loop: if this stop is already a continuation forced by a stop hook, let it pass.
  if (input.stop_hook_active) return;

  const transcript = input.transcript_path;
  if (!transcript || !fs.existsSync(transcript)) return;

  const text = lastAssistantText(transcript);
  if (!text) return;

  if (!hasLiveReadyToken(text)) return;          // no non-negated readiness token → allow
  const refs = harvest(text);
  if (refs.length) {
    // Scope a genuinely-bare `#N` to the repo the hook runs in (bare numbers collide across the
    // fleet repos + platform). A bare `#N` that also appears as a repo-qualified ref (the
    // "[owner/repo#N](…/pull/N)" report shape) is covered by that sibling, and a pure-URL report
    // needs no scoping — so resolve the current repo (a git-remote read) ONLY when a truly
    // uncovered bare ref remains. currentRepoSlug() is null when the cwd isn't a resolvable git
    // repo → hasFreshPass treats null (and cross-repo ambiguity) as BLOCK (block-biased, B6).
    const qualifiedNums = new Set(refs.filter(r => r.repo != null).map(r => r.pr));
    const currentRepo = refs.some(r => r.repo == null && !qualifiedNums.has(r.pr))
      ? currentRepoSlug(input.cwd || process.cwd())
      : null;
    if (!hasFreshPass(refs, currentRepo)) { blockReady(); return; }  // a numbered PR lacks a same-repo marker
  }
  // An UNNUMBERED PR mention ("the prod PR") can't be tied to a marker and can't be proven
  // to be a verified numbered ref without clause-reasoning → block. Fires even when every
  // numbered ref passed, else a URL/#N-spelled verified sibling suppresses it (outside-review
  // P1: "…pull/7 verified. The prod PR is ready"). Cost: a SAFE false-block on prose like
  // "the staging PR is ready: <url>" — avoided by naming the number.
  if (UNNUMBERED_PR.test(text)) blockReady();
}

// Readiness-positive tokens. Bounded alternation, no nested unbounded quantifiers →
// ReDoS-safe. "all green" and "0/zero/no unresolved" ARE claims — a terse "all green, 0
// unresolved" is itself a ready-signal — so a truthful not-ready report that also states
// them blocks (accepted by-design change). "done"/"finished" are deliberately NOT tokens:
// too overloaded to gate without the clause-reasoning this redesign removes.
const READY = /\bready\b|\bmergeable\b|\bshipped\b|good to (?:merge|go|ship)|safe to (?:merge|ship)|all\s+(?:checks\s+)?green|(?:\b0|\bzero|\bno)\s+unresolved|\bLGTM\b/gi;

// LOCAL adjacent negation — the ONLY cleverness. A token is negated iff a negator abuts
// it through only a bounded run of copula/adverb FILLER words (is/are/to/quite/…). A noun,
// comma, or clause boundary breaks it — so "no issues, ready" and the 2nd token in "…is
// not ready, but the docs are ready" are NOT negated (→ block). Anchored at end-of-prefix,
// run only against the ≤64 chars before the token → bounded, ReDoS-safe.
const NEG_ADJ = /(?:\bno longer|\bnot|\bnever|\bcannot|\bcan['’]?t|\bwon['’]?t|\bisn['’]?t|\baren['’]?t|\bwasn['’]?t|\bweren['’]?t|\bdon['’]?t|\bdoesn['’]?t|\bdidn['’]?t|\byet to be|\byet to)\s+(?:(?:is|are|am|be|been|being|was|were|to|now|yet|still|quite|fully|entirely|completely|really|actually|truly|necessarily|totally|going|gonna|get|getting|considered|deemed|marked|seem|seems|appear|appears|look|looks)\s+){0,4}$/i;

// An UNNUMBERED PR mention: a "PR"/"pull request" word NOT immediately followed by a number
// ("PR #7"/"PR 7"/"PRs #7" do NOT match; "the prod PR"/"pull request" do). `pull[\s-]+requests?`
// tolerates hyphen / multi-space / newline spellings ("pull-request", "pull  requests").
const UNNUMBERED_PR = /\b(?:PRs?|pull[\s-]+requests?)\b(?!\s*#?\d)/i;

function hasLiveReadyToken(text) {
  READY.lastIndex = 0;
  let m;
  while ((m = READY.exec(text)) !== null) {
    const pre = text.slice(Math.max(0, m.index - 64), m.index);  // bounded window (adjacency)
    if (!NEG_ADJ.test(pre)) return true;                          // an un-negated readiness token
  }
  return false;
}

// Harvest EVERY PR reference (absorbs old chunk B4.3). A `/pull/N` URL carries its repo
// and requires a SAME-repo marker (numbers collide across the 3 fleet repos, Codex P1); a
// bare `#N` or `PR N` carries no repo (repo:null) and is scoped to the current repo at
// match time in hasFreshPass (chunk B6). Greedy on purpose — an over-harvested ref
// only adds a SAFE marker requirement, while a MISSED ref that was the real claim would be
// a false-PASS, the one hazard we refuse. Plural/spelled-out/anaphoric all resolve here.
const HARVEST_URL = /github\.com\/([^/\s]+)\/([^/\s]+)\/pull\/(\d+)/gi;
const HARVEST_HASH = /#(\d+)/g;
const HARVEST_WORD = /\b(?:PRs?|pull[\s-]+requests?)\s*#?(\d+)/gi;
// List elision (Codex P1 + outside-review): an enumerated PR list — anchored by a `#N` or a
// PR-word ("PRs 7", mirroring HARVEST_WORD), continued over list connectors (punctuation
// `, & / +`, words `and`/`or`/`plus`, Oxford `, and`) — makes EVERY listed number a ref, so an
// elided later item (no `#`) is gated too ("#7 and 8", "#7, 8, and 9", "#7/8", "PRs 7 and 8").
// Each step consumes a connector + digits → no clause-crossing, ReDoS-safe. A bare space is NOT
// a connector (else "#7 3 commits" over-harvests), so space-only lists / spelled-out numbers
// are accepted misses (non-idiomatic). Greedy over-capture only ADDS a marker req (safe).
const HARVEST_LIST = /(?:#|\b(?:PRs?|pull[\s-]+requests?)\s*#?)\d+(?:\s*(?:,\s*(?:and|or)|and|or|plus|[,&\/+])\s*#?\d+)+/gi;
function harvest(text) {
  const refs = [];
  for (const m of text.matchAll(HARVEST_URL)) refs.push({ repo: `${m[1]}/${m[2]}`, pr: m[3] });
  for (const m of text.matchAll(HARVEST_HASH)) refs.push({ repo: null, pr: m[1] });
  for (const m of text.matchAll(HARVEST_WORD)) refs.push({ repo: null, pr: m[1] });
  for (const run of text.matchAll(HARVEST_LIST))
    for (const n of run[0].match(/\d+/g)) refs.push({ repo: null, pr: n });  // trailing elided items
  return refs;
}

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

// EVERY named PR ref must be satisfied by its OWN fresh PASS marker. A claim naming
// several PRs ("#7 and #9 are both ready") must not ride through on one sibling's
// marker — the staging-verified / prod-unverified multi-PR risk (outside-review P2.1).
// A repo-qualified ref (from a /pull/ URL) requires a SAME-REPO marker — a cross-repo
// #N collision must not satisfy it (Codex P1).
//
// A BARE `#N` ref (no repo in the text) is resolved against `currentRepo` — the repo the
// Stop hook is running in (chunk B6). Bare PR numbers collide across the 3 fleet repos +
// platform, so a bare "#9 is ready" must be satisfied ONLY by a fresh marker whose repo IS
// the current repo. Block-biased: if `currentRepo` is null (cwd not a resolvable git repo)
// OR the same bare `#N` has fresh markers under 2+ distinct repos (genuine ambiguity), it
// BLOCKS — a bare number we can't unambiguously scope must never ride an unrelated repo's
// marker (the pre-B6 false-PASS this closes).
function hasFreshPass(prRefs, currentRepo) {
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
    fresh.push({ repo: (mk.owner && mk.repo) ? normRepo(`${mk.owner}/${mk.repo}`) : null, pr: String(mk.pr) });
  }
  // A bare `#N` that co-occurs with a repo-qualified ref for the SAME number is that same PR
  // spelled twice — the canonical report "[owner/repo#9](…/pull/9)" harvests BOTH {o/r,9} and
  // {null,9}. The qualified sibling already enforces the same-repo marker, so the bare copy is
  // redundant; gating it against the cwd too would false-BLOCK a genuinely-verified URL claim
  // whenever the hook runs from a different repo's cwd (e.g. the /pm M window reporting a fleet
  // PR by URL). Skip such covered bare refs — this keeps the URL happy path un-regressed (B6).
  const qualifiedNums = new Set(prRefs.filter(r => r.repo != null).map(r => r.pr));
  for (const ref of prRefs) {
    if (ref.repo != null) {
      // Repo-qualified (from a /pull/ URL): a SAME-REPO fresh marker is required (Codex P1).
      // Compare case-insensitively — GitHub slugs are case-insensitive (Codex P2, B6R).
      if (!fresh.some(m => m.pr === ref.pr && m.repo === normRepo(ref.repo))) return false;
    } else if (!qualifiedNums.has(ref.pr)) {
      // Genuinely bare `#N` (no qualified sibling): scope it to the current repo; block on
      // ambiguity or an undeterminable cwd. Only real (non-null) marker repos count — a
      // malformed repo-less marker can neither satisfy a bare ref nor manufacture ambiguity.
      const reposForPr = new Set(fresh.filter(m => m.pr === ref.pr && m.repo != null).map(m => m.repo));
      if (reposForPr.size >= 2) return false;         // same #N fresh under 2+ repos → ambiguous → block
      if (currentRepo == null) return false;          // cwd not a resolvable repo → cannot scope → block
      if (!reposForPr.has(currentRepo)) return false; // no fresh marker for THIS repo's #N → block
    }
  }
  return true;
}

// Resolve the repo the Stop hook is running in (from its cwd) so a bare `#N` readiness claim
// can be tied to a specific repo's marker. Returns `owner/repo`, or null on any failure (cwd
// not a git repo / no `origin` / unparseable URL) — null is BLOCK-biased in hasFreshPass.
function currentRepoSlug(cwd) {
  try { return normRepo(parseRepoSlug(run('git', ['-C', String(cwd || '.'), 'remote', 'get-url', 'origin']))); }
  catch { return null; }
}
// Parse `owner/repo` from any remote-URL form — https, scp-like `git@host:owner/repo`,
// `ssh://…/owner/repo` — tolerating a trailing slash and a `.git` suffix. Bounded character
// classes, no nested/ambiguous quantifiers → ReDoS-safe.
function parseRepoSlug(url) {
  const s = String(url || '').trim().replace(/\/+$/, '').replace(/\.git$/i, '');
  const m = s.match(/[:/]([^/:\s]+)\/([^/:\s]+)$/);
  return m ? `${m[1]}/${m[2]}` : null;
}
// GitHub repo slugs are case-insensitive, but a marker's `owner/repo` (written from shipit's
// `verify <owner/repo>` argv) and the cwd's `origin` URL can differ in case. Normalize both
// sides to lower case before matching so a legitimately-verified same-repo ref isn't rejected
// on casing alone (Codex P2). Null-safe: preserves the block-biased null sentinel.
function normRepo(slug) { return slug == null ? null : String(slug).toLowerCase(); }

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
