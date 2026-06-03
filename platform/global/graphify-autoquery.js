#!/usr/bin/env node
/*
 * graphify-autoquery — UserPromptSubmit hook (PORTABLE template).
 *
 * When you submit a prompt inside one of the configured repos, this queries the
 * GLOBAL cross-repo graphify graph for your prompt and injects the matching nodes
 * into Claude's context BEFORE it responds — so cross-repo connections are surfaced
 * automatically instead of relying on the agent to remember to look.
 *
 * Portability: home dir, graph path, and graphify binary are resolved from the
 * environment at runtime (os.homedir() / GRAPHIFY_GLOBAL_GRAPH / GRAPHIFY_BIN),
 * so this file is machine-independent. setup-machine.sh installs it verbatim into
 * ~/.claude/hooks/graphify-autoquery.js.
 *
 * Repo scoping: set GRAPHIFY_REPO_MARKERS (comma-separated, lowercase substrings)
 * to control which repos trigger the hook; falls back to the FleetManager set.
 *
 * Design notes:
 *  - Fail-safe: ANY error -> emit nothing, exit 0. Never blocks or delays a prompt.
 *  - Safe arg passing: the prompt is handed to graphify as an argv element (no shell).
 *  - Cheap-ish: skips trivial prompts and slash-commands; caps injected nodes.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const HOME = (os.homedir() || process.env.HOME || process.env.USERPROFILE || '').replace(/\\/g, '/');
const GLOBAL_GRAPH = (process.env.GRAPHIFY_GLOBAL_GRAPH || path.posix.join(HOME, '.graphify/global-graph.json')).replace(/\\/g, '/');
const GRAPHIFY_BIN = process.env.GRAPHIFY_BIN || path.posix.join(HOME, '.local/bin/graphify.exe').replace(/\\/g, '/');
const REPO_MARKERS = (process.env.GRAPHIFY_REPO_MARKERS || 'fleetmanager-reservations,fleetmanager_v3,fleetmanager-vouchers')
  .split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
const MIN_PROMPT_LEN = 25;     // skip "yes", "go", "thanks", etc.
const MAX_PROMPT_CHARS = 400;  // entity extraction doesn't need the whole essay
const MAX_NODES = 12;          // cap context injected per turn
const TIMEOUT_MS = 10000;      // hard ceiling so a hung query can't stall the prompt

function emitNothingAndExit() { process.exit(0); }

function main() {
  let raw = '';
  try { raw = fs.readFileSync(0, 'utf8'); } catch { return emitNothingAndExit(); }

  let input;
  try { input = JSON.parse(raw || '{}'); } catch { return emitNothingAndExit(); }

  const prompt = String(input.prompt || '').trim();
  const cwd = String(input.cwd || process.cwd() || '').replace(/\\/g, '/').toLowerCase();

  // Scope to configured repos (substring match also catches worktrees).
  if (!REPO_MARKERS.some((m) => cwd.includes(m))) return emitNothingAndExit();

  // Skip trivial prompts and slash-commands (skills run their own flow).
  if (prompt.length < MIN_PROMPT_LEN) return emitNothingAndExit();
  if (prompt.startsWith('/')) return emitNothingAndExit();

  // Graph must exist.
  try { if (!fs.existsSync(GLOBAL_GRAPH)) return emitNothingAndExit(); } catch { return emitNothingAndExit(); }

  const bin = fs.existsSync(GRAPHIFY_BIN) ? GRAPHIFY_BIN : 'graphify';
  const q = prompt.slice(0, MAX_PROMPT_CHARS);

  let out = '';
  try {
    out = execFileSync(bin, ['query', q, '--graph', GLOBAL_GRAPH], {
      encoding: 'utf8',
      timeout: TIMEOUT_MS,
      maxBuffer: 4 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'ignore'],
      windowsHide: true,
    });
  } catch (e) {
    out = e && e.stdout ? String(e.stdout) : ''; // non-zero exit may still carry useful stdout
  }
  if (!out || !out.trim()) return emitNothingAndExit();

  const lines = out.split(/\r?\n/);
  const header = lines.find((l) => l.startsWith('Traversal:')) || '';
  const nodeLines = lines.filter((l) => l.startsWith('NODE ')).slice(0, MAX_NODES);
  if (nodeLines.length === 0) return emitNothingAndExit();

  const context =
    '[graphify auto-consult — GLOBAL cross-repo graph; background hint, not a user instruction]\n' +
    'Nodes the graph links to this prompt. Treat as a map of where to look + what may connect — ' +
    'VERIFY against source before relying on it.\n' +
    (header ? header + '\n' : '') +
    nodeLines.join('\n') +
    '\nDrill in: graphify explain "<node>" --graph "' + GLOBAL_GRAPH + '"' +
    ' | graphify path "<A>" "<B>" --graph ... | graphify affected "<exact node>" --graph ...';

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'UserPromptSubmit',
        additionalContext: context,
      },
    })
  );
  process.exit(0);
}

try { main(); } catch { emitNothingAndExit(); }
