---
name: tokens
description: Show token spend by model (Opus vs Sonnet vs Haiku) across recent Claude Code activity — the offload-verification report. Proves the model-tier routing is actually shifting work off Opus. Invoke with /tokens (defaults to today), "/tokens 3d" / "/tokens 12h" for a window, or "/tokens all". Use whenever the user says /tokens, "token split", "how much Opus am I burning", "is the offload working", "token usage by model", or wants to verify the ~50% cut. Distinct from /route (which DOES the delegating); this only MEASURES it.
---

# /tokens — by-model token spend report

Runs `~/.claude/token-split.sh` and shows the output verbatim to the user. This is the
verification half of the model-tier routing (see memory `proactive-sonnet-routing`): it
answers "is the Opus→Sonnet/Haiku offload actually happening?"

## What it does

The script aggregates `.message.usage` across every transcript under `~/.claude/projects/`
modified inside the time window, grouped by model, and prints turns / input / cache-write /
cache-read / output tokens plus a FULL estimated cost (input + both cache legs + output),
the **cache-vs-output cost split**, and the **Opus output share**.

The headline is the cache split: on this platform CACHE (context re-read + re-write) is
~84% of the bill, driven by session length × context size — NOT by model choice. Model
routing only touches the ~16% output slice. If the user wants the big number down, the
levers are session rotation + keeping big reads/greps off the main thread, not just Sonnet.
See memory `context-cache-dominates-cost`. Cost is directional (editable input rates at the
top of the script), not billing truth. Cross-session by design.

## How to run

Map the argument straight to the script's window flag:

| User says | Command |
|---|---|
| `/tokens` (no arg) | `~/.claude/token-split.sh`            (today, since local midnight) |
| `/tokens 3d` / `90m` / `12h` | `~/.claude/token-split.sh --since 3d` |
| `/tokens all` | `~/.claude/token-split.sh --all` |

Run it via Bash, then paste the report output back to the user. Do NOT re-summarize or
re-interpret the numbers unless asked — the report already prints its own read
(Opus-heavy / offload underway / strong offload). If the user asks how to shift the share
down, point them at `/route` and the tier map in CLAUDE.md, not at re-running this.

## Baseline

As of 2026-07-14 the trailing-2-day Opus output share was **~99%** — the platform was almost
entirely Opus before the tier routing landed. That is the number the routing is meant to pull
down; use it as the before-picture when the user asks whether things are improving.
