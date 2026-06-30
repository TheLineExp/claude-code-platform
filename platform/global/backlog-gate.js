#!/usr/bin/env node
/*
 * backlog-gate.js — PreToolUse hook on the Skill tool.
 *
 * Enforces Operating Doctrine Rule 4 (no unilateral backlog): nothing goes to
 * /todo or /feature unless Mike EXPLICITLY asked to park/defer that item. When
 * the Skill tool is invoked to ADD to the todo or feature backlog, force a
 * confirmation prompt so a model-initiated backlog can never pass silently.
 *
 * Mike's own "/todo add ..." is a one-tap confirm. A backlog the model tried to
 * sneak in shows up as a prompt he can DENY — at which point the work gets built
 * this session instead of shelved.
 *
 * FAILS OPEN on any error so it can never break the session.
 */

let raw = '';
process.stdin.on('data', (d) => (raw += d));
process.stdin.on('end', () => {
  try {
    const input = JSON.parse(raw || '{}');
    const tool = input.tool_name || input.toolName || '';
    const ti = input.tool_input || input.toolInput || {};
    const skill = String(ti.skill || '').trim().toLowerCase();
    const args = String(ti.args || '').trim();

    const isBacklogSkill = skill === 'todo' || skill === 'feature';
    const isAdd = /^add\b/i.test(args); // "add ...", "add --ops ...", etc.

    if (tool === 'Skill' && isBacklogSkill && isAdd) {
      const reason =
        'DOCTRINE RULE 4 — no unilateral backlog. About to file work to /' +
        skill +
        '. Approve ONLY if Mike EXPLICITLY asked to park / defer / backlog this ' +
        'specific item. If this is work that should be built now, DENY — the ' +
        'default is to build it this session, not shelve it.';
      process.stdout.write(
        JSON.stringify({
          hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: 'ask',
            permissionDecisionReason: reason,
          },
        })
      );
    }
  } catch (e) {
    // fail open — never break the session
  }
  process.exit(0);
});
