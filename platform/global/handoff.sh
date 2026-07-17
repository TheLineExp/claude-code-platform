#!/usr/bin/env bash
# handoff — session checkpoint / rotate / orient engine.
# The SCRIPT gathers hard facts; the MODEL writes the narrative snapshot.
#
#   handoff.sh where            cross-window roll-up: what's built where + where M is
#   handoff.sh gather [dir]     emit hard facts for the CURRENT window (model fills narrative)
#   handoff.sh resume [dir]     print the latest snapshot matching this window (re-seed)
#   handoff.sh list             list saved snapshots
#
# Snapshots live in ~/.claude/handoffs/<window>-<stamp>.md with a small YAML
# header (window/role/feature/repo/branch/worktree/phase/pr/next/updated) that
# `where` parses, followed by the model-written body.

set -uo pipefail

REPOS="${HANDOFF_REPOS:-/Users/mikekunz/Documents/Volo Technologies}"
PM_DIR="$HOME/.claude/pm"
SNAP_DIR="$HOME/.claude/handoffs"
MEMORY="$HOME/.claude/projects/-Users-mikekunz-Documents/memory/MEMORY.md"
mkdir -p "$SNAP_DIR"

# Shared per-window resolver. The canonical wc_anchor now lives here (handoff.sh no longer
# keeps a private copy — _window_anchor below delegates to it). Fail-open: if not deployed
# yet, _window_anchor's inline fallback keeps working, so resume behavior is unchanged.
WC_SH="$HOME/.claude/window-context.sh"
[ -f "$WC_SH" ] && . "$WC_SH"

# --- helpers ---------------------------------------------------------------

# Canonical active-work.md files ONLY — one per real repo. Every worktree carries
# a near-full COPY of the registry; scanning them all is slow and duplicative, so
# exclude worktree/chore/release suffixes (-w12, -x3, -relw1, -chore18, *sweep, *fu).
_active_work_files() {
  find "$REPOS" -maxdepth 3 -name active-work.md -path '*/.claude/*' 2>/dev/null | while read -r f; do
    repo=$(printf '%s' "$f" | rev | cut -d/ -f3 | rev)
    printf '%s' "$repo" | grep -qE '\-(w|x)[0-9]|\-rel|\-chore|prodfixups|sweep|fu$|throwaway' && continue
    echo "$f"
  done
}

# yaml header field from a snapshot file: _hdr <file> <key>
_hdr() {
  awk -v k="$2" '
    NR==1 && $0=="---"{inh=1; next}
    inh && $0=="---"{exit}
    inh && $0 ~ "^"k":"{sub("^"k":[[:space:]]*",""); print; exit}' "$1"
}

# Stable identity for THIS window that survives /clear. The claude process does
# NOT restart on /clear (that is the whole point — "rotate in the SAME window"),
# so its PID is a durable per-window key. Two windows = two claude processes =
# two anchors, even when they share a cwd AND branch (e.g. two M windows both on
# `staging` in the same main checkout — the exact case branch-matching couldn't
# tell apart). Walk up from the bash subshell to the claude native-binary.
#
# Canonical implementation now lives in window-context.sh (wc_anchor); this delegates so
# handoff and sitrep share ONE identity function. The inline block is a byte-identical
# fallback for the case where window-context.sh isn't deployed yet.
_window_anchor() {
  command -v wc_anchor >/dev/null 2>&1 && { wc_anchor; return; }
  local pid=$PPID cmd np i=0
  while [ "$i" -lt 6 ]; do
    cmd=$(ps -o command= -p "$pid" 2>/dev/null)
    case "$cmd" in
      *native-binary*|*/claude" "*|*/claude) echo "$pid"; return ;;
    esac
    np=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    { [ -z "$np" ] || [ "$np" = "$pid" ] || [ "$np" = "1" ] || [ "$np" = "0" ]; } && break
    pid=$np; i=$((i+1))
  done
  echo "$PPID"
}

# resolve a path through symlinks so ~/vt and its target compare equal
_realpath() { cd "$1" 2>/dev/null && pwd -P || echo "$1"; }

# print a snapshot as a resume payload
_emit_resume() {
  local f="$1" how="$2"
  echo "# Resuming from: $(basename "$f")"
  echo "_(matched on: $how)_"
  echo
  cat "$f"
}

# --- where: cross-window orient --------------------------------------------

cmd_where() {
  # First arg: "all" (no date filter) or a number of days (default 4).
  local days=4 filter_note cutoff_date
  if [ "${1:-}" = "all" ]; then days=99999; filter_note="all registrations"
  elif [ -n "${1:-}" ] && [ "$1" -eq "$1" ] 2>/dev/null; then days=$1; filter_note="last $days days"
  else filter_note="last $days days"; fi
  # ISO dates sort lexically = chronologically; compare strings (portable, no mktime).
  cutoff_date=$(date -v-"${days}"d +%Y-%m-%d 2>/dev/null || date -d "$days days ago" +%Y-%m-%d 2>/dev/null || echo "0000-00-00")

  echo "# Where things stand — $(date '+%Y-%m-%d %H:%M')"
  echo "_(active windows: $filter_note — \`handoff.sh where all\` for everything)_"
  echo

  echo "## Active windows (from registrations)"
  echo "_Branch names the feature. Deduped across main+worktree copies._"
  echo
  echo "| Window | Branch (= feature) | Registered |"
  echo "|---|---|---|"
  # Registry rows carry huge pipe-laden descriptions and are copied into each
  # worktree — so parse by REGEX (branch + date), not column position, and dedup
  # on branch keeping the newest date.
  local rows; rows=$(mktemp)
  while IFS= read -r awf; do
    [ -f "$awf" ] || continue
    grep -E '^\|.*feature/' "$awf" 2>/dev/null | while IFS= read -r row; do
      local br win d
      br=$(printf '%s' "$row" | grep -oE 'feature/[A-Za-z0-9._/-]+' | head -1)
      [ -z "$br" ] && continue
      win=$(printf '%s' "$row" | grep -oE '\bw[0-9]+\b' | head -1)
      d=$(printf '%s' "$row" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -1)
      [ -z "$d" ] && d="0000-00-00"
      printf '%s\t%s\t%s\n' "$d" "${win:-?}" "$br" >> "$rows"
    done
  done < <(_active_work_files)
  if [ -s "$rows" ]; then
    # newest-per-branch, then date-filter, then display newest-first
    sort -t$'\t' -k3,3 -k1,1r "$rows" | awk -F'\t' '!seen[$3]++' \
      | awk -F'\t' -v cut="$cutoff_date" '$1>=cut' \
      | sort -t$'\t' -k1,1r \
      | awk -F'\t' '{printf "| %s | %s | %s |\n",$2,$3,$1}'
  fi
  # empty-guard: recount after filtering
  local n; n=$(sort -t$'\t' -k3,3 -k1,1r "$rows" 2>/dev/null | awk -F'\t' '!seen[$3]++' | awk -F'\t' -v cut="$cutoff_date" '$1>=cut' | wc -l | tr -d ' ')
  [ "${n:-0}" -eq 0 ] && echo "| (no registrations in $filter_note) | | |"
  rm -f "$rows"
  echo

  # PM-tracked projects (where an M is coordinating)
  if ls -d "$PM_DIR"/*/ >/dev/null 2>&1; then
    echo "## M-tracked projects (multi-window / where M is)"
    echo
    for p in "$PM_DIR"/*/; do
      [ -d "$p" ] || continue
      local name; name=$(basename "$p")
      echo "### $name"
      if [ -f "$p/roster.md" ]; then
        # show non-placeholder roster rows
        if grep -qE '^\|[[:space:]]*w[0-9x]' "$p/roster.md" 2>/dev/null; then
          grep -E '^\|' "$p/roster.md" | sed 's/^/  /'
        else
          echo "  _(roster empty — M running, no dev windows checked in)_"
        fi
      fi
      # latest event for a heartbeat
      if [ -f "$p/roster-events.jsonl" ]; then
        local last; last=$(tail -1 "$p/roster-events.jsonl" 2>/dev/null)
        [ -n "$last" ] && echo "  last event: $last" | cut -c1-160
      fi
      echo
    done
  fi

  # Latest snapshot per window — phase + next action the registry doesn't hold
  if ls "$SNAP_DIR"/*.md >/dev/null 2>&1; then
    echo "## Last checkpoint per window (phase + next action)"
    echo
    echo "| Window | Role | Feature | Phase | Next action | PR |"
    echo "|---|---|---|---|---|---|"
    # newest snapshot per WINDOW (ls -t = newest first; awk keeps first seen).
    # Dedup on the anchor, not the display label — two M windows can both label
    # themselves "M" yet be different processes/projects; keying on window would
    # hide one. Fall back to window|feature for pre-anchor snapshots.
    # bash 3.2 on macOS has no associative arrays, so dedup in awk, not bash.
    local snaptmp; snaptmp=$(mktemp)
    for f in $(ls -t "$SNAP_DIR"/*.md 2>/dev/null); do
      local w a key; w=$(_hdr "$f" window); [ -z "$w" ] && w=$(basename "$f")
      a=$(_hdr "$f" anchor); key="$a"; [ -z "$key" ] && key="$w|$(_hdr "$f" feature)"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$w" "$(_hdr "$f" role)" "$(_hdr "$f" feature)" \
        "$(_hdr "$f" phase)" "$(_hdr "$f" next)" "$(_hdr "$f" pr)" >> "$snaptmp"
    done
    awk -F'\t' '!seen[$1]++{printf "| %s | %s | %s | %s | %s | %s |\n",$2,$3,$4,$5,$6,$7}' "$snaptmp"
    rm -f "$snaptmp"
    echo
    echo "_Deep backlog + prod state: ${MEMORY}_"
  fi
}

# --- gather: hard facts for the current window -----------------------------

cmd_gather() {
  local dir="${1:-$PWD}"
  cd "$dir" 2>/dev/null || true
  local anchor cwdp; anchor=$(_window_anchor); cwdp=$(_realpath "$dir")
  echo "## HANDOFF GATHER — hard facts (model: fill the narrative, then Write the snapshot)"
  echo "- when: $(date '+%Y-%m-%d %H:%M %Z')"
  echo "- cwd: $dir"
  echo "- window anchor: $anchor (this window's claude process — stable across /clear; unique per window)"

  local branch worktree root wlabel area
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -n "$branch" ]; then
    worktree="$root"
    echo "- branch: $branch"
    echo "- worktree: $worktree"
    echo "- uncommitted changes: $(git status --porcelain 2>/dev/null | wc -l | tr -d ' ') file(s)"
    echo "- recent commits:"
    git log --oneline -5 2>/dev/null | sed 's/^/    /'
    # open PR for this branch
    local pr; pr=$(gh pr list --head "$branch" --state open --json number,title,url 2>/dev/null)
    if [ -n "$pr" ] && [ "$pr" != "[]" ]; then
      echo "- open PR: $(echo "$pr" | jq -rc '.[0] | "#\(.number) \(.title) — \(.url)"' 2>/dev/null)"
    else
      echo "- open PR: none for $branch"
    fi
    # registry row matching this branch (current + main repo)
    echo "- registration:"
    local cand="$root/.claude/active-work.md"
    local gcd; gcd=$(git rev-parse --git-common-dir 2>/dev/null)
    [ -n "$gcd" ] && [ "$gcd" != ".git" ] && cand="$cand $(dirname "$gcd")/.claude/active-work.md"
    for f in $cand; do
      [ -f "$f" ] && grep -F "$branch" "$f" 2>/dev/null | sed 's/^/    /'
    done

    # Refresh THIS window's project record with current git location (fail-open; preserves
    # project/role/phase/next already set — only updates where the window is). Keeps /sitrep
    # and the statusline chip tracking this window even before the model writes the snapshot.
    if command -v wc_write >/dev/null 2>&1; then
      wc_write branch="$branch" worktree="$cwdp" repo="$(basename "$root")" >/dev/null 2>&1 || true
    fi
  else
    echo "- (not inside a git worktree — capture from conversation + MEMORY only)"
  fi

  # matching MEMORY lines (by branch token or worktree name)
  if [ -f "$MEMORY" ] && [ -n "$branch" ]; then
    local tok; tok=$(echo "$branch" | grep -oE 'w[0-9]+|x[0-9]+' | head -1)
    if [ -n "$tok" ]; then
      echo "- MEMORY hits for '$tok':"
      grep -iE "\b$tok\b|\($tok" "$MEMORY" 2>/dev/null | head -4 | sed 's/^/    /'
    fi
  fi

  # Exact, collision-proof write path. Filename carries the anchor + seconds so no
  # two windows (and no two checkpoints) ever overwrite each other. The leading slug
  # is a human-readable feature hint the model may refine; matching never depends on it.
  local stamp defslug snapfile
  stamp=$(date +%Y%m%d-%H%M%S)
  defslug=$(printf '%s' "${branch:-$(basename "$cwdp")}" | tr '/' '-' | tr -cd 'A-Za-z0-9._-')
  [ -z "$defslug" ] && defslug=win
  snapfile="$SNAP_DIR/${defslug}--a${anchor}-${stamp}.md"

  echo
  echo "## SNAPSHOT — Write (Write tool) EXACTLY to this path:"
  echo "   $snapfile"
  echo "   (Unique per window+time — never overwrites another window. You MAY change the"
  echo "    leading slug before '--' to a short feature kebab, but keep '--a${anchor}-${stamp}.md'.)"
  echo
  echo "Compose from the facts above PLUS what only this live session knows. Header first —"
  echo "copy 'anchor:' VERBATIM: it binds this snapshot to THIS window so '/handoff resume'"
  echo "after a /clear finds it and NOT another project's checkpoint on the same branch."
  echo
  echo "---"
  echo "window: <wX / M / solo>"
  echo "role: <dev | M | solo>"
  echo "feature: <one line — what's being built>"
  echo "repo: <repo name>"
  echo "branch: ${branch:-<none>}"
  echo "worktree: $cwdp"
  echo "anchor: $anchor"
  echo "phase: <planning | building | fix-round | review | shipping | blocked>"
  echo "pr: <#N or ->"
  echo "next: <the single next action, imperative>"
  echo "updated: $(date +%Y-%m-%dT%H:%M:%S%z)"
  echo "---"
  echo
  echo "AFTER writing the snapshot, stamp the live fields onto this window's project record so"
  echo "/sitrep and the statusline chip read them without re-deriving (fail-open; one line):"
  echo "   bash ~/.claude/window-context.sh write project=\"<project-or-feature-slug>\" \\"
  echo "     role=\"<dev|M|solo>\" phase=\"<phase>\" pr=\"<#N or ->\" next=\"<the next action>\""
  echo
  cat <<'SPEC'
## What's being built        (2-3 sentences, the goal + why)
## Current state             (what's done, what's in flight right now)
## Next action               (the exact next step to take on resume)
## Open threads / blockers    (decisions pending, review threads, risks)
## Key pointers              (file:line refs, PR links, related MEMORY entries)

Keep it DENSE — this replaces a 340k re-read context with ~3k. No narration of history
that doesn't change what to do next.
SPEC
}

# --- resume: print latest matching snapshot --------------------------------

# resume [dir] [slug]   or   resume [slug]
#   1) explicit slug/substring wins
#   2) else the snapshot bound to THIS window (anchor = same claude process) — definitive,
#      works even when two windows share cwd+branch (two M windows on staging)
#   3) else fall back to branch/cwd, but REFUSE to guess when >1 distinct project matches
#      (that silent wrong-project load was the bug) — list candidates and ask instead.
cmd_resume() {
  local dir="${1:-}" want="${2:-}"
  if [ -n "$dir" ] && [ ! -d "$dir" ]; then want="$dir"; dir="$PWD"; fi
  [ -z "$dir" ] && dir="$PWD"

  local anchor branch cwd files f
  anchor=$(_window_anchor)
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  cwd=$(_realpath "$dir")
  files=$(ls -t "$SNAP_DIR"/*.md 2>/dev/null)
  [ -z "$files" ] && { echo "No snapshots in $SNAP_DIR. Nothing to resume."; return 0; }

  # 1) explicit override
  if [ -n "$want" ]; then
    for f in $files; do
      if printf '%s' "$(basename "$f")" | grep -qiF "$want" || grep -qiF "$want" "$f" 2>/dev/null; then
        _emit_resume "$f" "explicit: '$want'"; return 0
      fi
    done
    echo "No snapshot matched '$want'.  See: handoff.sh list"; return 0
  fi

  # 2) THIS window — same claude process, survives /clear. Definitive.
  for f in $files; do
    [ "$(_hdr "$f" anchor)" = "$anchor" ] && { _emit_resume "$f" "this window (anchor $anchor)"; return 0; }
  done

  # 3) fall back to branch/cwd — guard against loading the WRONG project
  local cand="" feats="" hb hw
  for f in $files; do
    hb=$(_hdr "$f" branch); hw=$(_realpath "$(_hdr "$f" worktree)")
    if { [ -n "$branch" ] && printf '%s' "$hb" | grep -qiwF "$branch"; } \
       || { [ -n "$hw" ] && [ "$hw" = "$cwd" ]; }; then
      cand="$cand$f
"
      feats="$feats$(_hdr "$f" feature)
"
    fi
  done
  cand=$(printf '%s' "$cand" | sed '/^$/d')
  local ncand ndistinct
  ncand=$(printf '%s\n' "$cand" | sed '/^$/d' | wc -l | tr -d ' ')
  ndistinct=$(printf '%s' "$feats" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')

  if [ "${ncand:-0}" -eq 0 ]; then
    echo "No checkpoint for THIS window (anchor $anchor, branch '${branch:-none}', cwd $cwd)."
    echo "It hasn't checkpointed this process yet, or was saved before this fix added anchors."
    echo "Pick one explicitly:  handoff.sh resume <slug>    (see: handoff.sh list)"
    return 0
  fi
  if [ "${ndistinct:-1}" -le 1 ]; then
    _emit_resume "$(printf '%s\n' "$cand" | head -1)" "branch/cwd (unambiguous)"; return 0
  fi

  # AMBIGUOUS — the two-M-windows-on-staging case. Do NOT guess.
  echo "⚠️  Multiple projects match branch '${branch:-?}' / cwd $cwd, and none is bound to this"
  echo "    window's anchor ($anchor) — refusing to guess (that would load the wrong project)."
  echo "    Candidates:"
  echo
  printf '%s\n' "$cand" | while read -r f; do
    [ -f "$f" ] || continue
    printf '  %-44s  %s  [%s]\n' "$(basename "$f")" "$(_hdr "$f" feature)" "$(_hdr "$f" updated)"
  done
  echo
  echo "Resume the right one:  handoff.sh resume <slug-or-substring>   (a word from its feature)"
  return 0
}

# --- prune: archive stale registrations (non-destructive) ------------------

cmd_prune() {
  # handoff.sh prune [days] [--apply]   default 10 days, dry-run unless --apply
  local days=10 apply=false a
  for a in "$@"; do
    case "$a" in
      --apply) apply=true ;;
      ''|*[!0-9]*) : ;;   # non-numeric, ignore
      *) days=$a ;;
    esac
  done
  local cutoff; cutoff=$(date -v-"${days}"d +%Y-%m-%d 2>/dev/null || date -d "$days days ago" +%Y-%m-%d 2>/dev/null || echo "0000-00-00")
  echo "# Prune stale registrations — keep >= $cutoff (last $days days)"
  $apply || echo "_DRY RUN — add --apply to write. Stale rows move to active-work-archive.md (nothing deleted)._"
  echo

  while IFS= read -r f; do
    [ -f "$f" ] || continue
    local total keep arch tmp arcf
    total=$(grep -cE '^\|.*feature/' "$f")
    [ "$total" -eq 0 ] && continue
    arcf="$(dirname "$f")/active-work-archive.md"
    tmp=$(mktemp)
    # keep: header/non-feature lines + feature rows dated >= cutoff (or with NO date)
    awk -v cut="$cutoff" '
      /^\|.*feature\// {
        d=""; if (match($0,/[0-9]{4}-[0-9]{2}-[0-9]{2}/)) d=substr($0,RSTART,10);
        if (d!="" && d<cut) next;   # stale -> drop from keep
      }
      { print }' "$f" > "$tmp"
    keep=$(grep -cE '^\|.*feature/' "$tmp")
    arch=$((total-keep))
    printf "  %-28s %3d rows -> keep %3d, archive %3d\n" "$(basename "$(dirname "$(dirname "$f")")")" "$total" "$keep" "$arch"
    if $apply && [ "$arch" -gt 0 ]; then
      # append stale rows to archive (create header once)
      [ -f "$arcf" ] || printf '# Archived registrations (pruned by handoff)\n\n| Window | Branch | Worktree | Area | Started |\n|--------|--------|----------|------|---------|\n' > "$arcf"
      awk -v cut="$cutoff" '/^\|.*feature\// { d=""; if (match($0,/[0-9]{4}-[0-9]{2}-[0-9]{2}/)) d=substr($0,RSTART,10); if (d!="" && d<cut) print }' "$f" >> "$arcf"
      cp "$tmp" "$f"
    fi
    rm -f "$tmp"
  done < <(_active_work_files)
  echo
  $apply && echo "Done. Archives written alongside each active-work.md." \
         || echo "Re-run with --apply to perform the archive."
}

cmd_list() {
  echo "# Saved handoff snapshots"
  ls -t "$SNAP_DIR"/*.md 2>/dev/null | while read -r f; do
    printf "  %-40s  %s | %s\n" "$(basename "$f")" "$(_hdr "$f" feature)" "$(_hdr "$f" updated)"
  done
  [ -z "$(ls -A "$SNAP_DIR" 2>/dev/null)" ] && echo "  (none yet)"
}

case "${1:-where}" in
  where)  shift; cmd_where "$@" ;;
  gather) shift; cmd_gather "$@" ;;
  resume) shift; cmd_resume "$@" ;;
  prune)  shift; cmd_prune "$@" ;;
  list)   cmd_list ;;
  *) echo "usage: handoff.sh {where|gather [dir]|resume [dir]|prune [days] [--apply]|list}" >&2; exit 1 ;;
esac
