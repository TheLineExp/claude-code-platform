#!/usr/bin/env bash
# Claude Code status line for FleetManager development
# Reads JSON from stdin, outputs a compact status line

input=$(cat)

# --- Working directory ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir_name=$(basename "$cwd")

# --- Git branch (skip optional locks) ---
branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)

# --- Worktree label (from JSON or derived from branch) ---
worktree_name=$(echo "$input" | jq -r '.workspace.git_worktree // empty')

# --- Window/agent label ---
agent_name=$(echo "$input" | jq -r '.agent.name // empty')

# --- Model short name ---
model=$(echo "$input" | jq -r '.model.display_name // ""')

# --- Context usage ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# --- Build the line ---
parts=()

# Directory
parts+=("$(printf '\033[0;36m%s\033[0m' "$dir_name")")

# Git branch
if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
  if [ -n "$worktree_name" ]; then
    parts+=("$(printf '\033[0;33m[%s]\033[0m' "$branch")")
  else
    parts+=("$(printf '\033[0;33m(%s)\033[0m' "$branch")")
  fi
fi

# Project chip — THIS window's registered project[:chunk], so the window advertises what
# it's building at a glance. Fail-open by design: missing script / no record / any error →
# empty, and the chip is simply absent (never an error, never a stall). Tier-1 only (reads
# this window's own anchor record); no gh, no extra git — cheap enough for every render.
WC_SH="$HOME/.claude/window-context.sh"
if [ -f "$WC_SH" ]; then
  proj_chip=$(bash "$WC_SH" chip 2>/dev/null)
  if [ -n "$proj_chip" ]; then
    parts+=("$(printf '\033[0;32m⊳%s\033[0m' "$proj_chip")")
  fi
fi

# Agent name (if running under --agent)
if [ -n "$agent_name" ]; then
  parts+=("$(printf '\033[0;35magent:%s\033[0m' "$agent_name")")
fi

# Model
if [ -n "$model" ]; then
  parts+=("$(printf '\033[0;37m%s\033[0m' "$model")")
fi

# Context usage (only after first API call)
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  if [ "$used_int" -ge 80 ]; then
    color='\033[0;31m'   # red — critical
  elif [ "$used_int" -ge 50 ]; then
    color='\033[0;33m'   # yellow — moderate
  else
    color='\033[0;32m'   # green — healthy
  fi
  parts+=("$(printf "${color}ctx:%s%%\033[0m" "$used_int")")
fi

# --- Session length (marathon-session guard) ---
# Long sessions re-read the full context every turn — the audit's #1 token drain.
# Make it VISIBLE: turn count, dim normally, yellow when long, red "rotate" when very long.
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  turns=$(grep -c '"type":"assistant"' "$transcript" 2>/dev/null || echo 0)
  if [ "$turns" -ge 800 ]; then
    parts+=("$(printf '\033[0;31m⟳%s rotate\033[0m' "$turns")")
  elif [ "$turns" -ge 400 ]; then
    parts+=("$(printf '\033[0;33m⟳%s\033[0m' "$turns")")
  elif [ "$turns" -gt 0 ]; then
    parts+=("$(printf '\033[0;90m⟳%s\033[0m' "$turns")")
  fi
fi

# --- Opus output burn this session (offload gauge) ---
# Sums this session's own output tokens (main thread = Opus). The number you're
# trying to shrink; full by-model split is `~/.claude/token-split.sh`.
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  out_tok=$(jq -rs 'map(.message.usage.output_tokens // 0) | add // 0' "$transcript" 2>/dev/null || echo 0)
  if [ -n "$out_tok" ] && [ "$out_tok" -gt 0 ]; then
    if [ "$out_tok" -ge 1000000 ]; then
      disp=$(awk -v n="$out_tok" 'BEGIN{printf "%.1fM", n/1000000}')
    else
      disp=$(awk -v n="$out_tok" 'BEGIN{printf "%.0fk", n/1000}')
    fi
    parts+=("$(printf '\033[0;90m⊙%s out\033[0m' "$disp")")
  fi
fi

# Join with spaces
printf '%s' "${parts[0]}"
for part in "${parts[@]:1}"; do
  printf ' %s' "$part"
done
printf '\n'
