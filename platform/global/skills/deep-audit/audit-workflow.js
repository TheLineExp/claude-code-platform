export const meta = {
  name: 'deep-audit',
  description: 'Deliberate, budgeted deep multi-agent audit of a target subsystem — broad discovery, adversarially verified, ranked findings. Opt-in only; never auto-runs on ship.',
  phases: [
    { title: 'Scope', detail: 'map the target surface (files, entrypoints, writers)' },
    { title: 'Find', detail: 'multi-lens finders, loop until 2 dry rounds' },
    { title: 'Verify', detail: 'adversarial majority verify (default refuted)' },
    { title: 'Synthesize', detail: 'dedup, rank, completeness critic' },
  ],
}

// ---- inputs -------------------------------------------------------------
const target = (args && args.target) || 'the codebase'
const repos  = (args && args.repos) || '~/vt (fleetmanager-reservations, FM V3 / fleetmanager, fleetmanager-vouchers)'
const MAX_ROUNDS  = (args && args.maxRounds) || 6
const MAX_VERIFY  = (args && args.maxVerify) || 50
const FLOOR       = 60_000   // stop spawning new rounds if budget dips under this

// ---- the hunting lenses (discovery mode — the taxonomy, not diff-scoped) ----
const DIMENSIONS = [
  { key: 'money-concurrency', prompt:
    'Money & concurrency: TOCTOU / read-before-lock, CAS or lock bypass by a SIBLING writer '
    + '(enumerate every raw writer of each guarded row and prove it routes through the guard), '
    + 'webhook ordering/staleness, idempotency & double-fire, live-count-vs-immutable-history caps, '
    + 'failure paths that still mark a row paid/sent/complete, swallowed errors in charge/send wrappers.' },
  { key: 'parity-blast-radius', prompt:
    'Parity / blast radius: a behavior that exists on one surface but not its twins — list row vs detail vs '
    + 'modal vs printed/emailed receipt vs export; staff vs public vs kiosk route; org vs distributor; '
    + 'authenticate vs optionalAuth; the flag-OFF path (prod default), not just flag-ON; hand-rolled logic '
    + 'where a documented shared helper exists (it drifts from every sibling).' },
  { key: 'trust-auth', prompt:
    'Trust boundaries / fail-open: client-side-only enforcement, untrusted client fields (price, org id, ids) '
    + 'trusted server-side, endpoints missing the auth gate their siblings carry, guessable/decodable tokens, '
    + 'error paths that fail OPEN instead of closed.' },
  { key: 'legacy-data', prompt:
    'Legacy / pre-existing data semantics: how do rows minted BEFORE this code look to it? Backfilled []/null '
    + 'treated as "all", missing new stamps, `null !== null` predicates, `||` clobbering an intentional 0/""/false '
    + '(should be `??`), enum/status values the new set forgot.' },
  { key: 'error-edge', prompt:
    'Error & edge paths: the unhappy branch of every path — thrown vs returned errors, partial-failure cleanup, '
    + 'empty/zero/max inputs, aborted-midway state, provider timeout/throw leaving inconsistent rows.' },
  { key: 'root-cause-family', prompt:
    'Root cause, not symptom: for any defect you find, does it have SIBLINGS sharing the same defect (other '
    + 'branches of the conditional, other call sites of the shared resolver/helper)? Report the FAMILY and the '
    + 'shared fix location, not just one instance.' },
]

// ---- schemas ------------------------------------------------------------
const FINDING_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: { findings: { type: 'array', items: {
    type: 'object', additionalProperties: false,
    properties: {
      title:     { type: 'string' },
      severity:  { type: 'string', enum: ['P1','P2','P3'] },
      file:      { type: 'string' },
      line:      { type: 'integer' },
      dimension: { type: 'string' },
      scenario:  { type: 'string', description: 'concrete inputs/interleaving -> wrong result' },
      why:       { type: 'string' },
      fixLocus:  { type: 'string', description: 'the shared place to fix (helper/resolver), if a family' },
      inTarget:  { type: 'boolean', description: 'false if real but outside the named target' },
    },
    required: ['title','severity','file','scenario'],
  } } },
  required: ['findings'],
}
const SCOPE_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    files:       { type: 'array', items: { type: 'string' } },
    entrypoints: { type: 'array', items: { type: 'string' } },
    guardedRows: { type: 'array', items: { type: 'string' }, description: 'money/state rows or models in scope' },
    notes:       { type: 'string' },
  },
  required: ['files'],
}
const VERDICT_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    real:       { type: 'boolean' },
    confidence: { type: 'string', enum: ['high','medium','low'] },
    reason:     { type: 'string' },
  },
  required: ['real','reason'],
}

const sev = s => ({ P1: 0, P2: 1, P3: 2 }[s] ?? 3)
const key = f => `${(f.file||'').toLowerCase()}:${f.line||''}:${(f.title||'').toLowerCase().slice(0,60)}`

// ---- Scope --------------------------------------------------------------
phase('Scope')
const scope = await agent(
  `Map the audit surface for: "${target}".\nRepos: ${repos}.\n`
  + `Enumerate the files, entrypoints (routes/jobs/webhooks/cron/kiosk), and the money/state rows or Prisma models `
  + `this target reads or writes. Be concrete with paths. This grounds a deep bug hunt — err toward including a `
  + `file if it plausibly touches the target. Do NOT hunt bugs yet; just map the surface.`,
  { label: 'scope', phase: 'Scope', schema: SCOPE_SCHEMA, model: 'sonnet' }
)
const surface = [
  'FILES:\n' + ((scope && scope.files) || []).map(f => '  ' + f).join('\n'),
  (scope && scope.entrypoints && scope.entrypoints.length) ? 'ENTRYPOINTS:\n' + scope.entrypoints.map(f => '  ' + f).join('\n') : '',
  (scope && scope.guardedRows && scope.guardedRows.length) ? 'GUARDED ROWS/MODELS:\n' + scope.guardedRows.map(f => '  ' + f).join('\n') : '',
  (scope && scope.notes) ? 'NOTES: ' + scope.notes : '',
].filter(Boolean).join('\n')
log(`scoped ${((scope && scope.files) || []).length} files for "${target}"`)

// ---- Find (loop until dry / budget / round cap) -------------------------
phase('Find')
const seen = new Set()
const fresh = []
let dry = 0, round = 0
while (dry < 2 && round < MAX_ROUNDS && (!budget.total || budget.remaining() > FLOOR)) {
  round++
  const batches = await parallel(DIMENSIONS.map(d => () =>
    agent(
      `Deep audit round ${round}. Hunt the "${d.key}" lens in target: "${target}".\n\nSURFACE:\n${surface}\n\n`
      + `LENS: ${d.prompt}\n\nRead the actual code — full functions and their direct call sites, follow money/state `
      + `rows across writers. Report ONLY concrete, refutation-ready findings: each needs file:line, a specific `
      + `failing scenario (inputs/interleaving -> wrong outcome), and why the code as written fails it. `
      + `No style notes, no "consider". Mark inTarget=false if real but outside "${target}". `
      + `If you pass ~150 tool calls you are spelunking too far — stop and return what you have.`,
      { label: `find:${d.key}#${round}`, phase: 'Find', schema: FINDING_SCHEMA }
    )
  ))
  const found = batches.filter(Boolean).flatMap(b => (b.findings || []))
  const newOnes = found.filter(f => !seen.has(key(f)))
  if (!newOnes.length) { dry++; log(`round ${round}: dry (${dry}/2)`); continue }
  dry = 0
  newOnes.forEach(f => seen.add(key(f)))
  fresh.push(...newOnes)
  log(`round ${round}: +${newOnes.length} candidates (${fresh.length} total)`)
}
if (round >= MAX_ROUNDS && dry < 2) log(`hit round cap (${MAX_ROUNDS}) — more may remain; re-run to continue`)

// prioritize + cap verify (no silent truncation)
fresh.sort((a, b) => sev(a.severity) - sev(b.severity))
let toVerify = fresh
if (fresh.length > MAX_VERIFY) {
  toVerify = fresh.slice(0, MAX_VERIFY)
  log(`CAP: ${fresh.length} candidates found, verifying top ${MAX_VERIFY} by severity — ${fresh.length - MAX_VERIFY} lower-severity deferred (re-run with higher maxVerify to cover)`)
}

// ---- Verify (majority of 3 diverse skeptics, default refuted) -----------
phase('Verify')
const LENSES = ['correctness', 'security/abuse', 'does-it-actually-reproduce']
const verified = await parallel(toVerify.map(f => () =>
  parallel(LENSES.map(lens => () =>
    agent(
      `Adversarially verify this finding through the "${lens}" lens. Your DEFAULT is real=false — only real=true `
      + `if you can trace the concrete failure in the actual code. Read the cited code before deciding.\n\n`
      + `FINDING: ${f.title}\nAT: ${f.file}:${f.line || '?'}\nSEVERITY: ${f.severity}\nSCENARIO: ${f.scenario}\n`
      + `${f.why ? 'CLAIMED CAUSE: ' + f.why + '\n' : ''}`,
      { label: `verify:${(f.file || '').split('/').pop()}`, phase: 'Verify', schema: VERDICT_SCHEMA }
    )
  )).then(vs => {
    const votes = (vs || []).filter(Boolean)
    const yes = votes.filter(v => v.real).length
    return { ...f, real: yes >= 2, votesFor: yes, votesTotal: votes.length }
  })
))
const confirmed = verified.filter(Boolean).filter(f => f.real).sort((a, b) => sev(a.severity) - sev(b.severity))

// ---- Synthesize + completeness critic -----------------------------------
phase('Synthesize')
const critic = await agent(
  `We deep-audited "${target}" over ${round} round(s) and CONFIRMED ${confirmed.length} findings `
  + `(${confirmed.filter(f => f.severity === 'P1').length} P1). Confirmed titles:\n`
  + confirmed.map(f => `- [${f.severity}] ${f.title} (${f.file})`).join('\n')
  + `\n\nAs a skeptical completeness critic: what did this audit likely MISS? Name specifics — a lens not fully run, `
  + `a file/path in the surface not read, a writer not enumerated, a claim left unverified. Short and concrete.`,
  { label: 'completeness', phase: 'Synthesize', model: 'sonnet' }
)

return {
  target,
  rounds: round,
  hitRoundCap: round >= MAX_ROUNDS && dry < 2,
  candidates: fresh.length,
  confirmedCount: confirmed.length,
  inTarget: confirmed.filter(f => f.inTarget !== false),
  outsideTarget: confirmed.filter(f => f.inTarget === false),
  completenessNote: critic,
  budgetSpentTokens: budget.spent ? budget.spent() : null,
}
