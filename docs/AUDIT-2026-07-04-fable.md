# Fable Deep Audit — 2026-07-04

Four adversarial Fable agents (hook-correctness, token-efficiency, workflow-coherence,
agent/skill-quality) + an insider pass. All hook bypasses below were **empirically verified
by running `git`**. This is the durable work-list; fix in fresh sessions, batched by theme.

## META-FINDING (explains "installing it doesn't feel different")

The consolidation's **canonical layer is clean** (`platform/global/` ↔ `~/.claude` is
byte-identical, zero drift, ~3.3K standing tokens). But **two halves never reached the
working environment**:

1. **The fleet-repo half of the consolidation (audit Track A2) was never finished**, and
2. **The local fleet checkouts are stale** — `~/vt/Fleetmanager_V3` is **30 commits behind
   origin/staging**, so the merged deletions/slims aren't in the working tree. Reservations'
   local checkout is on an old feature branch.

So every fleet session still loads the OLD per-repo skills/agents/hooks and the un-slimmed
CLAUDE.mds. The fix landed on origin; your machine never pulled it. **Merging ≠ deployed.**

---

## THEME A — Guard hooks are porous (VERIFIED bypasses; live globally)

> **STATUS 2026-07-04 (batch #2 executed):** A1–A11 + B1 all fixed in the canonical hooks.
> Root cause across A1/A2/A3/A9/A10: guards matched the RAW command string — fixed by
> quote-blanked per-segment matching in `_parse-input.sh` (`COMMAND_NOSTR`/`GIT_SEGMENTS`,
> also strips env-assignment/wrapper prefixes and `git -C`-style global opts). A8: new
> `_fleet_shaped` (fail-closed on `.claude/` presence) gates block-protected-branch;
> worktree hooks still use `_fleet_active`. A7: quote-aware writer-target lexing in
> block-file-redirect (sed -i/cp/mv/dd/sponge + `>|`); arbitrary interpreters
> (`python -c`) remain a documented residual — FS-layer enforcement is the real fix.
> Decision (Mike, batch #2): `MERGE_POLICY=block-all` is intended policy, now HARDCODED in
> `_config.sh` (dead platform.config.json lookup + allow-staging branch removed — a config
> override is itself a silent policy-downgrade vector). Adversarial suite at
> `platform/tests/hook-bypass-suite.sh` (111 cases incl. the A9 must-PASS strings):
> reproduced 49 failures pre-fix, 0 post-fix. Re-run it on EVERY hook edit.

| # | Sev | File | Bypass (verified) | Fix |
|---|---|---|---|---|
| A1 | **P1** | block-protected-branch.sh:36,31 | `^git` anchor: `cd wt && git push origin master`, `VAR=1 git push origin master`, `true; git push origin master` all SKIP the guard → direct push to a deploy branch | drop `^`, match `(^|[^[:alnum:]_.-])git[[:space:]]+(commit\|push\|merge)\b` (mirror _parse-input's own detection) |
| A2 | **P1** | block-no-verify.sh:8 | `git commit -n` (short form) skips all hooks | also match `-[a-zA-Z]*n\b` on a git commit |
| A3 | **P1** | block-protected-branch.sh:31 | `git push origin HEAD:refs/heads/staging` (name after `/`) | include `/` and `refs/heads/<name>` in the refspec match |
| A4 | P2 | block-destructive-git.sh:19 | `git push origin +HEAD:feature/x` force-updates without `--force` | block leading-`+` refspecs |
| A5 | P2 | block-destructive-git.sh:24 | `git reset --h HEAD~1` (git accepts prefixes) | match `--h(a(r(d)?)?)?` or gate on reset minus `--soft/--mixed` |
| A6 | P2 | block-destructive-git.sh:29 | `git checkout -- .`, `git restore .`, `git checkout . ` (trailing space), `git checkout ./` | broaden to `(checkout\|restore)…(--\s+)?\.(/)?` |
| A7 | P2 | block-file-redirect.sh / _parse-input.sh:45 | non-redirect writers bypass the worktree-write guard: `cp`, `mv`, `sed -i`, `dd of=`, `python -c open('w')`, `sponge` | detect `sed -i`, `cp/mv` into repo, `dd of=`, or enforce at FS layer |
| A8 | P2 | _parse-input.sh:56 (`_fleet_active`) | an emptied/corrupted active-work.md → **all fleet guards no-op** (fail-open) — can then push to master in a real fleet repo | gate protected-branch on branch identity, not on active-work rows; fail-closed when `.claude/` exists but rows absent |
| A9 | P2 | block-no-verify.sh:8; block-destructive-git.sh | FALSE POSITIVE: `git commit -m "...--no-verify..."`, and any read-only `grep`/`echo` containing the force-push literal, are BLOCKED (blocked this audit twice) | only match real flag tokens on a git command, not inside `-m`/`-F` values or non-git commands |
| A10 | P3 | block-gh-merge.sh:9,36 | non-POSIX `\s` (GNU-only) → fails-open on a grep without it | use `[[:space:]]` (as _parse-input already does) |
| A11 | P3 | session-guard.js:56 | counts `indexOf('"type":"assistant"')` over whole blob — the substring appears in tool output → over-counts/fires early; `readFileSync` whole transcript every prompt; markers never GC'd | count line-start only; skip when file < ~1.2MB; prune old markers |

## THEME B — Deny-list vs hook contradiction

- **B1 (P2)** `settings.json` deny `Bash(git push --force*)` also matches `--force-with-lease`,
  which block-destructive-git deliberately ALLOWS. Permission-deny wins → the safe
  rebase-then-push variant is blocked at the permission layer. Fix: narrow the deny rule so it
  doesn't swallow `--force-with-lease`.

## THEME C — Fleet consolidation incomplete + stale local checkouts

> **STATUS 2026-07-04 (batch #1 executed):** All 3 local checkouts pulled to merged
> origin/staging (C2 ✅ — V3's 46-agent pack + 10 skills gone; reservations slim landed via
> pull, so C4's 37.9K measurement was the stale checkout). V3#1229 + vouchers#322 were already
> merged; **reservations#1449 verified green (checks pass, 0 unresolved threads) but agents
> cannot merge (block-all policy) — Mike merges.** Remainder shipped as cross-repo x1 PRs:
> reservations#1453 (pathway line + delete retired `.claude/agents/agents/`), V3#1232 (hooks
> claim + Available Skills rewrite), vouchers#323 (pathway line + hook wording + registry
> prune + window-id sentinel). Worktree GC: 7 merged worktrees removed (reservations);
> `fleetmanager-vouchers-chore18` is merged but DIRTY — needs Mike's eyes. Stale
> active-work rows pruned: 85→40 / 37→18 / 31→26 (merged-only; unmerged-stale rows left
> registered). NOT yet done: none of C3's substance remains — the graphify-first
> contradiction claimed in C3/C4 no longer exists in the pulled CLAUDE.mds.

- **C1 (P1)** All 3 fleet repos still carry per-repo skills/agents (git-tracked in the local
  checkout): reservations `.claude/skills/{letsbuild,shipit,code-review,pre-deploy,feature,
  api-review,security-review}` + nested `.claude/agents/agents/`; V3 10 skills + 18 persona
  agents; vouchers old letsbuild/shipit/pre-deploy. They load alongside the globals → the exact
  two-`shipit`/two-`letsbuild` pathway conflict the platform exists to kill. (The MERGED
  consolidation PRs removed some on origin; the hook-cleanup PRs #1449/#1229/#322 remove the
  hooks — both blocked by the stale local checkout + un-merged PRs.)
- **C2 (P1)** V3 local checkout 30 commits behind origin/staging → 46-agent "studio" pack still
  in the working tree = **~9.8K tokens injected into every V3 session**. Fix: pull the fleet
  checkouts to the merged origin/staging (carefully — reservations is on a feature branch).
- **C3 (P1)** All 3 fleet CLAUDE.mds mandate the RETIRED pathway `/letsbuild → develop →
  /pre-deploy → /shipit` ("run all 4 review skills") — contradicts the canonical `/code-review`
  + parity-sweep + money-concurrency inside `/shipit`. In-repo instructions override by
  proximity. Fix: rewrite the three workflow sections to the platform pathway.
- **C4 (P1)** reservations CLAUDE.md still 37,905 chars (~9.5K tok) — the `feature/s-slim-claudemd`
  slim (Jun 16) never landed. All 3 repo CLAUDE.mds contain a live contradiction: repo rule 1
  "Graphify **first** — consult the graph before planning" vs global "graphify — optional aid,
  **never a gate**"; and claim to be "mirrored in ~/.claude" (no longer true).

## THEME D — Deployability broken (the "deployable global solution" claim)

- **D1 (P1)** `traceability-review/SKILL.md:64-126` (canonical AND live in ~/.claude) scripts
  `cd "C:\Users\MichaelKunz\..."` — every command fails on this Mac; also prescribes retired
  `/pre-deploy`. Fix: Mac paths (or `~/vt`), drop `/pre-deploy`.
- **D2 (P2)** "Template substitution" is fiction: docs claim `{{HOME}}`/`{{REPOS_ROOT}}` are
  substituted at sync; `setup-machine.sh` does plain `cp`. `/Users/mikekunz` hardcoded in the
  settings template (the `node "/Users/mikekunz/.claude/hooks/*.js"` hook commands break for any
  other user), pm/letsbuild/shipit SKILLs, and traceability-reviewer agent. Fix: use `~` in the
  two node hook commands + implement substitution OR rewrite docs to match reality.
- **D3 (P1)** `setup.sh:21` sets `PLATFORM_HOOKS="$SCRIPT_DIR/.claude/hooks"` — that dir doesn't
  exist → script exits immediately; its whole purpose (install per-repo hooks) contradicts the
  global model. `setup-repos.sh:66` still points users at it. Fix: delete setup.sh + the pointer.
- **D4 (P2)** Docs describe non-existent behavior: `setup-machine.sh` never writes
  `~/.claude/backlog-location` (SETUP/ARCHITECTURE/TROUBLESHOOTING + todo/feature skills claim it
  does → `/todo`//`/feature` fall to fallback on a fresh Mac); backups go to `~/.claude/backups/
  <ts>/` not `*.bak-N`; session-guard.js + the global hook mirror are documented nowhere.

## THEME E — Review-agent gaps (the core value-add is weaker than it looks)

- **E1 (P1, one-line)** `money-concurrency-reviewer.md:5` `model: inherit` → invoked from a
  Sonnet-routed context (route is standing policy) the adversarial money review silently runs on
  **Sonnet**. Fix: `model: opus`. **✅ FIXED 2026-07-04** — applied in `platform/global/agents/`
  and synced to `~/.claude` (`--diff` clean); uncommitted in claude-code-platform.
- **E2 (P2)** parity-sweep is structurally blind to the helper-bypass writer (`_withSettlementLock`
  class): it greps CHANGED symbols, finding consumers but never a raw `prisma.x.update` that
  skips the new lock. No repo map (can't locate portal/vouchers to sweep siblings). Weak grep
  hygiene (bare `rg -n` → cross-function FPs). Fixes: add executable writer-mapping grep
  (`rg -n "prisma\.<model>\.(update|updateMany|upsert|delete)|\$executeRaw"` → every hit must
  route through the lock); add the 3-repo map; use `rg -nw`/`-nF`/receiver-qualified patterns.
- **E3 (P2)** PR-Ready gate is **prose-only**; audit rec B3 said "skill OR hook." The failure it
  targets (skipping prose ~25×) is the same control class that already failed. Fix: a script that
  runs `gh pr checks` + the unresolved-thread count and writes a verification marker; a
  Stop/PreToolUse hook blocks "ready/done" claims without a fresh marker.
- **E4 (P2)** shipit Step 1b uses model-judgment to decide if the diff is money/state (misclassify
  → gate never fires); needs a mechanical grep like the ship-gate customer-contact one. shipit
  has a Step 6/7/8 ordering contradiction ("tooling failed its own review" class).
- **E5 (P2)** Audit failure classes with NO guard: known-helpers-ignored (`apiErrorText`, `??`,
  React-Query invalidation), root-defect-re-patched-across-PRs (nothing checks "was this
  file/function flagged before"), giant-PR size (no check in shipit). traceability-reviewer omits
  vouchers.

## THEME F — Dead/stale references

- route/SKILL.md:39,87,92,68 → `/gstack-review`, `/pre-deploy`, `code-reviewer` agent (all retired).
- CUSTOMIZATION.md:71-76 + TROUBLESHOOTING.md:37-45 teach the retired per-repo-hooks model
  (opposite of the global model) → edits land where they never deploy.
- `_config.sh` + block-protected-branch.sh reference the deleted `platform.config.json`.
- `platform/global/codex-config.template.toml` unreferenced stray; reservations
  `hook-bypass-log.md` (105KB tracked); nested `.claude/agents/agents/`.

## THEME G — Token weights (hard numbers; chars/4 ≈ tokens)

- graphify SKILL.md **58,117 chars (~14.5K tok)** — heaviest, still monolithic (bundles
  neo4j/svg/graphml/video-export bash inline). Split → ~6K core + lazy `reference/`.
- shipit SKILL.md 32,602 (~8.1K); split the same way.
- V3 46-agent pack ~9.8K tok/session (= C2). reservations CLAUDE.md ~9.5K (= C4).
- traceability-reviewer agent DESCRIPTION 1,894 chars (3 `<example>` blocks) loaded every
  session everywhere → trim to ~400.
- 4 copies each of letsbuild/shipit (global + 3 repos, all different sizes) → collapse to global.

---

## Recommended fix batches (one fresh session each)

1. **Hook hardening (Theme A + B)** — the verified P1 bypasses. Root-cause in canonical hooks,
   test each against the exact bypass strings above, re-sync. Highest severity (live global).
2. **Fleet sync + cleanup (Theme C)** — pull local checkouts to merged origin/staging; merge the
   open hook-cleanup PRs #1449/#1229/#322; delete residual per-repo skills/agents; rewrite the 3
   fleet CLAUDE.md workflow sections + land the reservations slim. Biggest *felt* win (kills the
   9.8K V3 tax + the pathway contradictions).
3. **Deployability (Theme D)** — Mac-ify traceability-review; `~` in node hook commands;
   delete setup.sh; add backlog-location write; fix the setup docs.
4. **Agent strengthening (Theme E)** — ~~money-reviewer `model: opus`~~ (✅ done 2026-07-04);
   parity-sweep writer-mapping + repo map + grep hygiene; make PR-Ready a real hook.
5. **Token slim (Theme G)** — split graphify + shipit into core + lazy reference; trim
   traceability desc; collapse skill copies.

Global config is clean; the leaks and holes are all in the fleet-repo half and the hooks.
