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

# Join with spaces
printf '%s' "${parts[0]}"
for part in "${parts[@]:1}"; do
  printf ' %s' "$part"
done
printf '\n'
