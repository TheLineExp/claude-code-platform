#!/usr/bin/env node
/**
 * session-guard.js — UserPromptSubmit hook.
 *
 * Marathon sessions were the #1 token drain in the 2026-07 audit: one session
 * carrying feature → review → ship → verify → the next feature ran 3,000+ turns
 * and re-read its full context EVERY turn (1.6B cache-read tokens observed).
 *
 * This nudges a rotation at natural boundaries. On each user prompt it counts the
 * session's turns from the transcript and, at two tiers, injects a ONE-TIME
 * reminder (a per-session+tier marker prevents nagging). It never blocks and
 * fails open — any error exits 0 with no output.
 *
 * Output: text on stdout is added to the prompt's context (UserPromptSubmit
 * contract), so the model sees the reminder and relays it to the user.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

// Turn tiers (assistant messages ≈ turns/tool-steps). Tuned to the audit: the
// worst sessions were 3,000+; nudge well before that, escalating once.
const TIERS = [
  { name: 'strong', turns: 800 },
  { name: 'gentle', turns: 400 },
];

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch { return ''; }
}

function main() {
  let input;
  try { input = JSON.parse(readStdin() || '{}'); } catch { return; }

  const transcript = input.transcript_path;
  const sessionId = input.session_id || 'unknown';
  if (!transcript || !fs.existsSync(transcript)) return;

  // Cheap turn proxy: count assistant messages in the JSONL transcript.
  let turns = 0;
  try {
    const data = fs.readFileSync(transcript, 'utf8');
    // Count line-anchored assistant events without a regex over the whole blob.
    let idx = 0;
    const needle = '"type":"assistant"';
    while ((idx = data.indexOf(needle, idx)) !== -1) { turns++; idx += needle.length; }
  } catch { return; }

  const tier = TIERS.find(t => turns >= t.turns);
  if (!tier) return;

  // Fire once per (session, tier). Marker dir under the OS temp dir — no repo writes.
  const markerDir = path.join(os.tmpdir(), 'claude-session-guard');
  const marker = path.join(markerDir, `${sanitize(sessionId)}.${tier.name}`);
  try {
    if (fs.existsSync(marker)) return;
    fs.mkdirSync(markerDir, { recursive: true });
    fs.writeFileSync(marker, String(turns));
  } catch { return; }

  const strong = tier.name === 'strong';
  const msg = strong
    ? `[session-guard] This session is very long (~${turns} turns). Long sessions re-read the FULL context every turn — the audit's #1 token drain. Unless you're mid-task, finish the current unit of work and tell the user to start a FRESH session (rotate at the next ship/verify boundary). Say this to the user proactively.`
    : `[session-guard] This session is getting long (~${turns} turns). At the next natural boundary (after a ship/verify completes), recommend the user start a fresh session — long sessions re-read the whole context each turn. Mention it once; don't nag.`;

  process.stdout.write(msg + '\n');
}

function sanitize(s) { return String(s).replace(/[^A-Za-z0-9_.-]/g, '_').slice(0, 80); }

try { main(); } catch { /* fail open */ }
process.exit(0);
