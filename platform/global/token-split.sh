#!/usr/bin/env bash
# token-split — by-model token spend across recent Claude Code activity.
# Proves the Opus→Sonnet/Haiku offload is actually happening.
#
# Usage:
#   ~/.claude/token-split.sh              # today (since local midnight)
#   ~/.claude/token-split.sh --since 3d   # last 3 days   (also: 12h, 90m)
#   ~/.claude/token-split.sh --all        # all transcripts on disk
#
# Reads every *.jsonl transcript under ~/.claude/projects/ modified inside the
# window and sums input / cache-read / cache-write / output tokens per model.
# Cross-session by design: it answers "what did my whole platform spend by
# model", which is the offload question — not a single-session view.
#
# Cost is the FULL estimate — fresh input + cache-write + cache-read + output —
# because on long sessions CACHE (read+write) is 80%+ of the real bill, not
# output. Rates are INPUT $/MTok, EDITABLE; the script derives the rest with the
# standard multipliers (output = 5x input, cache-write = 1.25x, cache-read =
# 0.1x). Directional signal, not billing truth.

set -euo pipefail

# --- editable rate table ($ per million INPUT tokens) ---
RATE_opus=15
RATE_sonnet=3
RATE_haiku=0.80
RATE_fable=3
RATE_other=3

PROJECTS="$HOME/.claude/projects"

# --- parse args -> cutoff epoch ---
since_epoch=0
label="all time"
if [ "${1:-}" = "--all" ]; then
  since_epoch=0; label="all time"
elif [ "${1:-}" = "--since" ] && [ -n "${2:-}" ]; then
  spec="$2"; num="${spec%[a-zA-Z]}"; unit="${spec##*[0-9]}"
  case "$unit" in
    m) secs=$((num*60));;
    h) secs=$((num*3600));;
    d) secs=$((num*86400));;
    *) echo "bad --since (use 90m / 12h / 3d)"; exit 1;;
  esac
  since_epoch=$(( $(date +%s) - secs )); label="last $spec"
else
  # default: since local midnight today
  since_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) 00:00:00" +%s 2>/dev/null \
                || date -d "today 00:00:00" +%s)
  label="today"
fi

# --- gather files in window ---
files=()
while IFS= read -r f; do files+=("$f"); done < <(
  find "$PROJECTS" -name '*.jsonl' -type f 2>/dev/null | while read -r f; do
    mt=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
    [ "$mt" -ge "$since_epoch" ] && echo "$f"
  done
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "No transcripts modified in window ($label)."; exit 0
fi

# --- aggregate with one jq pass over all files ---
printf '%s\n' "${files[@]}" | tr '\n' '\0' | xargs -0 cat 2>/dev/null | jq -rs '
  map(select(.message.usage and .message.model))
  | group_by(.message.model)
  | map({
      model: .[0].message.model,
      inp:   (map(.message.usage.input_tokens // 0)              | add),
      cw:    (map(.message.usage.cache_creation_input_tokens//0) | add),
      cr:    (map(.message.usage.cache_read_input_tokens // 0)   | add),
      out:   (map(.message.usage.output_tokens // 0)             | add),
      turns: length
    })
  | .[] | [.model, .turns, .inp, .cw, .cr, .out] | @tsv
' | sort -t"$(printf '\t')" -k6 -nr | awk -F'\t' -v label="$label" \
    -v r_opus="$RATE_opus" -v r_son="$RATE_sonnet" -v r_hai="$RATE_haiku" \
    -v r_fab="$RATE_fable" -v r_oth="$RATE_other" '
  function h(n){ if(n>=1e6)return sprintf("%.1fM",n/1e6); if(n>=1e3)return sprintf("%.1fk",n/1e3); return n"" }
  function rate(m){ if(m~/opus/)return r_opus; if(m~/sonnet/)return r_son; if(m~/haiku/)return r_hai; if(m~/fable/)return r_fab; return r_oth }
  function shortm(m){ gsub(/^claude-/,"",m); return m }
  BEGIN{
    printf "\n  Token spend by model — %s\n", label
    printf "  %-16s %6s %9s %9s %9s %9s %9s\n","MODEL","TURNS","INPUT","CACHE-W","CACHE-R","OUTPUT","~COST"
    printf "  %s\n","---------------------------------------------------------------------------------"
  }
  {
    model=$1; turns=$2; inp=$3; cw=$4; cr=$5; out=$6
    if(inp+cw+cr+out==0) next
    rin=rate(model)
    # full cost: output=5x input, cache-write=1.25x, cache-read=0.1x
    cost=(inp*rin + cw*1.25*rin + cr*0.10*rin + out*5*rin)/1e6
    cachecost=(cw*1.25*rin + cr*0.10*rin)/1e6
    tot_out+=out; tot_cost+=cost; tot_turns+=turns; tot_cache+=cachecost
    printf "  %-16s %6d %9s %9s %9s %9s %8.0f$\n", shortm(model), turns, h(inp), h(cw), h(cr), h(out), cost
    if(model~/opus/){opus_out+=out; opus_cost+=cost} else other_out+=out
  }
  END{
    printf "  %s\n","---------------------------------------------------------------------------------"
    printf "  %-16s %6d %9s %9s %9s %9s %8.0f$\n","TOTAL",tot_turns,"","","",h(tot_out),tot_cost
    if(tot_cost>0){
      cshare=100*tot_cache/tot_cost
      printf "\n  Cache (context) = %.0f%% of cost.  Output = only %.0f%%.\n", cshare, 100-cshare
      if(cshare>=70) printf "  → Cost is dominated by CONTEXT SIZE, not model choice. End long sessions;\n    keep big reads/greps off the main thread. Model routing helps output only.\n"
    }
    if(tot_out>0){
      share=100*opus_out/tot_out
      printf "  Opus output share: %.0f%%   (model-routing target: keep dropping)\n", share
    }
    print ""
  }'
