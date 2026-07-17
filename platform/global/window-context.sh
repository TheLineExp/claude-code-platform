#!/usr/bin/env bash
# window-context.sh — the ONE shared per-window project resolver.
#
# THE BUG THIS FIXES: there was no per-window project record anywhere on disk, so
# /sitrep fell back to the single machine-global ~/.claude/pm/.active-project and every
# window reported whichever project last ran `/pm init`. This file gives each window a
# durable record keyed by its claude PROCESS (the same anchor /handoff already uses),
# so "which project is THIS window on?" has a real, per-window answer.
#
# Storage:  ~/.claude/windows/a<anchor>.json   (one file per live window)
#   fields: anchor,pid,window,role,project,chunk,repo,branch,worktree,base,pr,phase,next,updated
#   A dead PID = a stale record (wc_reap drops them). branch+worktree are also stored so a
#   window still resolves after a reboot kills the PID (tier-2 fallback below).
#
# Used two ways:
#   • SOURCED  by sitrep.sh / handoff.sh / statusline (functions wc_*)
#   • CLI      by the letsbuild / pm skills:  window-context.sh write project=foo role=M ...
#
# Resolution order (wc_resolve_project), mirrors handoff.sh cmd_resume's refuse-to-guess:
#   1) THIS window's own record (anchor = this claude process) — definitive
#   2) else a live record whose branch OR worktree matches this cwd — used only if UNIQUE
#   3) else nothing (caller refuses and lists candidates) — never a silent global fallback

# NOTE: no `set -e` — this file is sourced into other scripts and must never abort them.
set -uo pipefail 2>/dev/null || true

WC_HOME="${WC_HOME:-$HOME/.claude/windows}"

# --- identity --------------------------------------------------------------

# Stable identity for THIS window that survives /clear. The claude process does NOT
# restart on /clear, so its PID is a durable per-window key; two windows = two claude
# processes = two anchors even when they share cwd AND branch. Walk up from the bash
# subshell to the claude native-binary. (Canonical copy — handoff.sh sources this.)
wc_anchor() {
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

# Is <pid> still a live claude process? (staleness test for OTHER windows' records)
wc_pid_alive() {
  local p="${1:-}" cmd
  [ -n "$p" ] || return 1
  cmd=$(ps -o command= -p "$p" 2>/dev/null) || return 1
  [ -n "$cmd" ] || return 1
  case "$cmd" in
    *native-binary*|*/claude" "*|*/claude) return 0 ;;
  esac
  return 1
}

wc_dir() { mkdir -p "$WC_HOME" 2>/dev/null; printf '%s' "$WC_HOME"; }
wc_file() { printf '%s/a%s.json' "$(wc_dir)" "${1:-$(wc_anchor)}"; }
_wc_realpath() { cd "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }

# --- write / read ----------------------------------------------------------

# wc_write k=v [k=v ...]   — upsert THIS window's record, preserving unset fields.
# Values may contain spaces (e.g. next="do the thing"); everything after the first
# '=' is the value. anchor/pid/updated are stamped automatically.
wc_write() {
  command -v jq >/dev/null 2>&1 || return 1
  local anchor file base out now kv k v n=0
  anchor=$(wc_anchor)
  file=$(wc_file "$anchor")
  base='{}'
  if [ -f "$file" ]; then
    base=$(cat "$file" 2>/dev/null)
    printf '%s' "$base" | jq empty >/dev/null 2>&1 || base='{}'
  fi
  local -a jqargs=()
  local filter='.'
  for kv in "$@"; do
    case "$kv" in *=*) : ;; *) continue ;; esac
    k="${kv%%=*}"; v="${kv#*=}"
    jqargs+=(--arg "k$n" "$k" --arg "v$n" "$v")
    filter="$filter | .[\$k$n]=\$v$n"
    n=$((n+1))
  done
  now=$(date +%Y-%m-%dT%H:%M:%S%z)
  jqargs+=(--arg _a "$anchor" --arg _p "$anchor" --arg _u "$now")
  filter="$filter | .anchor=\$_a | .pid=\$_p | .updated=\$_u"
  out=$(printf '%s' "$base" | jq "${jqargs[@]}" "$filter" 2>/dev/null) || return 1
  printf '%s\n' "$out" > "$file.tmp$$" 2>/dev/null && mv "$file.tmp$$" "$file" 2>/dev/null
}

# wc_get <key> [anchor]   — one field from a record (empty if absent)
wc_get() {
  command -v jq >/dev/null 2>&1 || return 1
  local key="$1" f; f=$(wc_file "${2:-$(wc_anchor)}")
  [ -f "$f" ] || return 1
  jq -r --arg k "$key" '.[$k] // empty' "$f" 2>/dev/null
}

# wc_read [anchor]  — dump a record
wc_read() { local f; f=$(wc_file "${1:-$(wc_anchor)}"); [ -f "$f" ] && cat "$f"; }

# --- seed (for a window that will OPEN ELSEWHERE) --------------------------

# A "seed" is a record written by one window (e.g. /letsbuild in the setup window) FOR a
# window that will open later in a worktree — so that dev window's very first /sitrep and its
# statusline already show the right project, before it has checkpointed its own anchor record.
# Keyed by worktree path (no live pid). Matched by tier-2 branch/worktree resolution while the
# worktree dir exists; the window's own anchor record (tier 1) supersedes it on first write.
_wc_seed_key() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }
wc_seed_file() { printf '%s/seed-%s.json' "$(wc_dir)" "$(_wc_seed_key "$1")"; }

# wc_seed worktree=<abs> [project=..] [branch=..] [role=..] [chunk=..] [repo=..] [base=..]
wc_seed() {
  command -v jq >/dev/null 2>&1 || return 1
  local kv k v wt=""
  for kv in "$@"; do case "$kv" in worktree=*) wt="${kv#worktree=}" ;; esac; done
  [ -n "$wt" ] || return 1
  wt=$(_wc_realpath "$wt")                        # normalize so chip/scan keys agree
  local file; file=$(wc_seed_file "$wt")
  local -a jqargs=(); local filter='.'; local n=0
  for kv in "$@"; do
    case "$kv" in *=*) : ;; *) continue ;; esac
    k="${kv%%=*}"; v="${kv#*=}"
    [ "$k" = "worktree" ] && v="$wt"              # store the normalized path
    jqargs+=(--arg "k$n" "$k" --arg "v$n" "$v"); filter="$filter | .[\$k$n]=\$v$n"; n=$((n+1))
  done
  local now; now=$(date +%Y-%m-%dT%H:%M:%S%z)
  jqargs+=(--arg _u "$now" --arg _s seed)
  filter="$filter | .updated=\$_u | .source=\$_s"
  local out; out=$(jq -n "${jqargs[@]}" "$filter" 2>/dev/null) || return 1
  printf '%s\n' "$out" > "$file.tmp$$" 2>/dev/null && mv "$file.tmp$$" "$file" 2>/dev/null
}

# --- resolve ---------------------------------------------------------------

# Is this record still "current"? A live-anchor record: pid must be a live claude process.
# A seed or backfill record has no live pid of its own (it stands in for a window that will
# open, or was reconstructed from a snapshot), so it stays current while its worktree exists.
_wc_record_current() {
  local f="$1" src pid wt
  src=$(jq -r '.source // empty' "$f" 2>/dev/null)
  case "$src" in
    seed|backfill)
      wt=$(jq -r '.worktree // empty' "$f" 2>/dev/null)
      [ -n "$wt" ] && [ -d "$wt" ] ;;
    *)
      pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)
      wc_pid_alive "$pid" ;;
  esac
}

# Echo the project slugs of every CURRENT record (live anchor OR live seed) whose branch OR
# worktree matches ($1 branch, $2 cwd). One slug per line.
wc_scan_projects() {
  command -v jq >/dev/null 2>&1 || return 0
  local branch="${1:-}" cwd="${2:-}" f proj wt
  for f in "$(wc_dir)"/a*.json "$(wc_dir)"/seed-*.json; do
    [ -f "$f" ] || continue
    proj=$(jq -r '.project // empty' "$f" 2>/dev/null); [ -n "$proj" ] || continue
    _wc_record_current "$f" || continue
    if [ -n "$branch" ] && [ "$(jq -r '.branch // empty' "$f" 2>/dev/null)" = "$branch" ]; then
      printf '%s\n' "$proj"; continue
    fi
    wt=$(jq -r '.worktree // empty' "$f" 2>/dev/null)
    if [ -n "$wt" ] && [ "$(_wc_realpath "$wt")" = "$cwd" ]; then
      printf '%s\n' "$proj"
    fi
  done
}

# wc_resolve_project [dir]  — print THIS window's project slug and return 0, or
# return 1 (none, or ambiguous — caller must refuse and list candidates).
wc_resolve_project() {
  local dir="${1:-$PWD}" anchor file p branch cwd matches ndistinct
  anchor=$(wc_anchor)
  file=$(wc_file "$anchor")
  # tier 1 — this window's own record (definitive, even after reboot the file is ours)
  if [ -f "$file" ]; then
    p=$(jq -r '.project // empty' "$file" 2>/dev/null)
    [ -n "$p" ] && { printf '%s\n' "$p"; return 0; }
  fi
  # tier 2 — a UNIQUE live record matching this branch/cwd (handles post-reboot new PID)
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  cwd=$(_wc_realpath "$dir")
  matches=$(wc_scan_projects "$branch" "$cwd" | sed '/^$/d' | sort -u)
  ndistinct=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "${ndistinct:-0}" -eq 1 ]; then printf '%s\n' "$matches"; return 0; fi
  return 1
}

# wc_list  — every live window record, one line each (for refuse-to-guess candidate lists
# and /handoff where). Format: anchor \t role \t project \t chunk \t branch \t worktree
wc_list() {
  command -v jq >/dev/null 2>&1 || return 0
  local f
  for f in "$(wc_dir)"/a*.json "$(wc_dir)"/seed-*.json; do
    [ -f "$f" ] || continue
    local state; if _wc_record_current "$f"; then state="live"; else state="stale"; fi
    jq -r --arg a "$state" '[(.anchor // "seed"),.role,.project,.chunk,.branch,.worktree,$a] | map(. // "-") | @tsv' "$f" 2>/dev/null
  done
}

# wc_reap  — drop records that are no longer current (dead anchor pid, or seed/backfill whose
# worktree is gone), and drop a seed/backfill once a REAL live-anchor window exists for the
# same worktree (its own anchor record has superseded the stand-in).
wc_reap() {
  local f n=0 wt src pid
  # worktrees that have a real, live anchor record (NOT seed/backfill — those don't supersede).
  local live_wts="|"
  for f in "$(wc_dir)"/a*.json; do
    [ -f "$f" ] || continue
    src=$(jq -r '.source // empty' "$f" 2>/dev/null)
    case "$src" in seed|backfill) continue ;; esac
    pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)
    wc_pid_alive "$pid" || continue
    wt=$(jq -r '.worktree // empty' "$f" 2>/dev/null)
    [ -n "$wt" ] && live_wts="$live_wts$(_wc_realpath "$wt")|"
  done
  for f in "$(wc_dir)"/a*.json "$(wc_dir)"/seed-*.json; do
    [ -f "$f" ] || continue
    if ! _wc_record_current "$f"; then rm -f "$f" && n=$((n+1)); continue; fi
    src=$(jq -r '.source // empty' "$f" 2>/dev/null)
    case "$src" in
      seed|backfill)
        wt=$(_wc_realpath "$(jq -r '.worktree // empty' "$f" 2>/dev/null)")
        case "$live_wts" in *"|$wt|"*) rm -f "$f" && n=$((n+1)) ;; esac ;;
    esac
  done
  printf 'reaped %d stale/superseded window record(s)\n' "$n"
}

# wc_chip  — compact "project:chunk" (or "project") for the statusline. Fail-open:
# prints nothing on any error / missing record. Tier-1 only (no branch scan) to stay cheap.
wc_chip() {
  command -v jq >/dev/null 2>&1 || return 0
  local f p c
  f=$(wc_file)                                   # tier 1: this window's own anchor record
  if [ ! -f "$f" ]; then
    f=$(wc_seed_file "$(_wc_realpath "$PWD")")   # fallback: a worktree seed for this cwd
  fi
  [ -f "$f" ] || return 0
  p=$(jq -r '.project // empty' "$f" 2>/dev/null); [ -n "$p" ] || return 0
  c=$(jq -r '.chunk // empty' "$f" 2>/dev/null)
  if [ -n "$c" ] && [ "$c" != "-" ]; then printf '%s:%s' "$p" "$c"; else printf '%s' "$p"; fi
}

# wc_backfill  — seed records from the newest handoff snapshot per anchor (reduces the
# "no record → refuse" friction for windows that predate this system). Idempotent; only
# fills a record that doesn't already exist for that anchor. Reads YAML headers.
wc_backfill() {
  command -v jq >/dev/null 2>&1 || return 1
  local snapdir="$HOME/.claude/handoffs" f a hdr seen="|" n=0
  [ -d "$snapdir" ] || { echo "no snapshots"; return 0; }
  local hdrget
  # newest first so the first snapshot seen per anchor wins
  for f in $(ls -t "$snapdir"/*.md 2>/dev/null); do
    a=$(awk 'NR==1&&$0=="---"{i=1;next} i&&$0=="---"{exit} i&&/^anchor:/{sub(/^anchor:[[:space:]]*/,"");print;exit}' "$f")
    [ -n "$a" ] || continue
    case "$seen" in *"|$a|"*) continue ;; esac
    seen="$seen$a|"
    [ -f "$(wc_file "$a")" ] && continue   # already has a live record
    local role feat repo branch wt phase pr next
    role=$(awk 'NR==1&&$0=="---"{i=1;next} i&&$0=="---"{exit} i&&/^role:/{sub(/^role:[[:space:]]*/,"");print;exit}' "$f")
    feat=$(awk 'NR==1&&$0=="---"{i=1;next} i&&$0=="---"{exit} i&&/^feature:/{sub(/^feature:[[:space:]]*/,"");print;exit}' "$f")
    repo=$(awk 'NR==1&&$0=="---"{i=1;next} i&&$0=="---"{exit} i&&/^repo:/{sub(/^repo:[[:space:]]*/,"");print;exit}' "$f")
    branch=$(awk 'NR==1&&$0=="---"{i=1;next} i&&$0=="---"{exit} i&&/^branch:/{sub(/^branch:[[:space:]]*/,"");print;exit}' "$f")
    wt=$(awk 'NR==1&&$0=="---"{i=1;next} i&&$0=="---"{exit} i&&/^worktree:/{sub(/^worktree:[[:space:]]*/,"");print;exit}' "$f")
    phase=$(awk 'NR==1&&$0=="---"{i=1;next} i&&$0=="---"{exit} i&&/^phase:/{sub(/^phase:[[:space:]]*/,"");print;exit}' "$f")
    pr=$(awk 'NR==1&&$0=="---"{i=1;next} i&&$0=="---"{exit} i&&/^pr:/{sub(/^pr:[[:space:]]*/,"");print;exit}' "$f")
    next=$(awk 'NR==1&&$0=="---"{i=1;next} i&&$0=="---"{exit} i&&/^next:/{sub(/^next:[[:space:]]*/,"");print;exit}' "$f")
    # backfilled records are keyed by the snapshot's anchor, not this process's — write directly
    local out; out=$(jq -n \
      --arg anchor "$a" --arg pid "$a" --arg role "${role:-}" --arg project "${feat:-}" \
      --arg repo "${repo:-}" --arg branch "${branch:-}" --arg worktree "${wt:-}" \
      --arg phase "${phase:-}" --arg pr "${pr:-}" --arg next "${next:-}" \
      --arg updated "$(date +%Y-%m-%dT%H:%M:%S%z)" --arg src "backfill" \
      '{anchor:$anchor,pid:$pid,role:$role,project:$project,repo:$repo,branch:$branch,worktree:$worktree,phase:$phase,pr:$pr,next:$next,updated:$updated,source:$src}' 2>/dev/null)
    [ -n "$out" ] && printf '%s\n' "$out" > "$(wc_file "$a")" && n=$((n+1))
  done
  printf 'backfilled %d window record(s) from snapshots\n' "$n"
}

# --- CLI dispatch (only when executed, not when sourced) -------------------
# shellcheck disable=SC2128
if [ "${BASH_SOURCE:-$0}" = "$0" ]; then
  cmd="${1:-}"; shift 2>/dev/null || true
  case "$cmd" in
    anchor)   wc_anchor ;;
    write)    wc_write "$@" ;;
    seed)     wc_seed "$@" ;;
    get)      wc_get "$@" ;;
    read)     wc_read "$@" ;;
    resolve)  wc_resolve_project "$@" ;;
    list)     wc_list ;;
    reap)     wc_reap ;;
    chip)     wc_chip ;;
    backfill) wc_backfill ;;
    *) echo "usage: window-context.sh {anchor|write k=v...|seed worktree=..|get <key>|read|resolve|list|reap|chip|backfill}" >&2; exit 1 ;;
  esac
fi
