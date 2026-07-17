#!/usr/bin/env bash
# sitrep.sh — gather hard facts for a /sitrep report.
#
# The SCRIPT gathers facts. The MODEL writes the narrative in the canonical shape
# (~/.claude/skills/sitrep/FORMAT.md): recap, then numbered paste-order next steps.
#
# Usage:
#   sitrep.sh gather [project]   hard facts for one project (default: THIS window's project)
#   sitrep.sh list               every known project, one line each
#   sitrep.sh prs                open PRs across all repos, with merge URLs
#   sitrep.sh resolve <name>     print the resolved project dir (or candidates)

set -uo pipefail

PM_DIR="$HOME/.claude/pm"
MEM_DIR="$HOME/.claude/projects/-Users-mikekunz-Documents/memory"
VT="$HOME/vt"   # space-free symlink to "Volo Technologies"

# Shared per-window resolver (anchor-keyed). This is what makes the no-arg /sitrep report
# THIS window's project instead of the machine-global ~/.claude/pm/.active-project (the bug:
# every window inherited whichever project last ran `/pm init`). Sourced, not re-implemented.
WC_SH="$HOME/.claude/window-context.sh"
[[ -f "$WC_SH" ]] && source "$WC_SH"

# repo-key | gh-repo | default base branch | canonical checkout
REPOS=(
    "fleetmanager-reservations|TheLineExp/fleetmanager-reservations|staging|$VT/fleetmanager-reservations"
    "Fleetmanager_V3|TheLineExp/Fleetmanager_V3|staging|$VT/Fleetmanager_V3"
    "fleetmanager-vouchers|TheLineExp/fleetmanager-vouchers|staging|$VT/fleetmanager-vouchers"
)

have_gh() { command -v gh >/dev/null 2>&1; }

# ---------------------------------------------------------------- resolve

# Resolve a project name to a dir under ~/.claude/pm.
# Prints the dir on a unique hit; prints "AMBIGUOUS"/"NONE"/"NO_WINDOW_CONTEXT" + info otherwise.
#
# NO-ARG behavior (the /sitrep default) is anchor-first, NOT global:
#   - ask window-context.sh for THIS window's project (anchor -> branch/cwd fallback)
#   - if it resolves, resolve that slug like a named project below
#   - if it does NOT (no record, or ambiguous across windows), return NO_WINDOW_CONTEXT and
#     REFUSE — never silently fall back to ~/.claude/pm/.active-project (that global fallback
#     WAS the bug this whole change fixes).
resolve_project() {
    local q="${1:-}"
    if [[ -z "$q" ]]; then
        local wproj=""
        if command -v wc_resolve_project >/dev/null 2>&1; then
            wproj=$(wc_resolve_project 2>/dev/null) || wproj=""
        fi
        if [[ -n "$wproj" ]]; then
            q="$wproj"   # fall through to named resolution below
        else
            echo "NO_WINDOW_CONTEXT"; return 3
        fi
    fi

    if [[ -d "$PM_DIR/$q" ]]; then echo "$PM_DIR/$q"; return 0; fi

    local hits=() d
    for d in "$PM_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local base; base=$(basename "$d")
        [[ "$base" == "archive" ]] && continue
        if [[ "$base" == *"$q"* ]]; then hits+=("$base"); fi
    done

    if [[ ${#hits[@]} -eq 1 ]]; then echo "$PM_DIR/${hits[0]}"; return 0; fi
    if [[ ${#hits[@]} -gt 1 ]]; then
        echo "AMBIGUOUS"
        printf '%s\n' "${hits[@]}"
        return 2
    fi
    echo "NONE"; return 1
}

# ---------------------------------------------------------------- memory

_mem_skip() {  # index/backup files are not memories
    local b="$1"
    [[ "$b" == "MEMORY.md" || "$b" == "MEMORY-ARCHIVE.md" || "$b" == *.bak ]]
}

# Rank memory files by word-stem overlap with the project slug. Exact-slug matching is
# far too strict: PM slugs and memory slugs are named independently
# (vouchers-booking-flow-improvements vs line-voucher-checkout-drop-fix), and plurals
# differ (vouchers/voucher) — so match on 5-char stems and score by overlap.
memory_hits() {
    local q="$1"
    [[ -d "$MEM_DIR" ]] || { echo "(no memory dir)"; return 0; }

    local stopwords=" the and for with from into plus fix fixes issue issues work "
    local -a stems=()
    local tok
    for tok in ${q//-/ }; do
        tok=$(echo "$tok" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')
        [[ ${#tok} -ge 4 ]] || continue
        [[ "$stopwords" == *" $tok "* ]] && continue
        stems+=("${tok:0:5}")   # stem: survives plurals (voucher/vouchers -> vouch)
    done

    # With many stems, a 1-stem hit is noise ("booking" matches half the memory dir).
    # Demand real overlap once we have enough stems to demand it.
    local min_score=1
    [[ ${#stems[@]} -ge 3 ]] && min_score=2

    local f found=0
    local seen="|"
    local -a scored=()
    for f in "$MEM_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        local base; base=$(basename "$f")
        _mem_skip "$base" && continue
        local lbase; lbase=$(echo "$base" | tr '[:upper:]' '[:lower:]')

        # exact slug in filename == certain hit
        if [[ "$lbase" == *"$q"* ]]; then
            echo "- $f  (exact slug)"; found=1; seen="$seen$f|"; continue
        fi
        local score=0 s
        for s in "${stems[@]}"; do
            [[ "$lbase" == *"$s"* ]] && score=$((score+1))
        done
        [[ $score -ge $min_score ]] && scored+=("$score|$f")
    done

    if [[ ${#scored[@]} -gt 0 ]]; then
        while IFS='|' read -r score f; do
            [[ "$seen" == *"|$f|"* ]] && continue
            echo "- $f  (name overlap: $score/${#stems[@]} — VERIFY relevance before citing)"
            found=1; seen="$seen$f|"
        done < <(printf '%s\n' "${scored[@]}" | sort -t'|' -k1,1nr | head -5)
    fi

    # content match on the full slug, capped
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        _mem_skip "$(basename "$f")" && continue
        [[ "$seen" == *"|$f|"* ]] && continue
        echo "- $f  (content match)"; found=1; seen="$seen$f|"
    done < <(grep -ril --include='*.md' -- "$q" "$MEM_DIR" 2>/dev/null | head -4)

    if [[ $found -eq 0 ]]; then
        echo "(no memory file matched \"$q\" — that is NOT proof none exists."
        echo " Grep the index yourself before concluding: $MEM_DIR/MEMORY.md)"
    fi
    return 0
}

# ---------------------------------------------------------------- PRs

pr_lines_for_repo() {
    local key="$1" ghrepo="$2" base="$3"
    have_gh || { echo "  (gh not available)"; return 0; }
    local out
    out=$(gh pr list --repo "$ghrepo" --state open --limit 60 \
        --json number,title,url,headRefName,baseRefName,isDraft,mergeStateStatus,reviewDecision,statusCheckRollup,updatedAt \
        --jq '.[]
              | ([.statusCheckRollup[]? | (.conclusion // .state // "PENDING")]) as $cs
              | (if ($cs|length)==0 then "no-checks"
                 elif ($cs | any(. == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "CANCELLED")) then "RED"
                 elif ($cs | any(. == "PENDING" or . == "IN_PROGRESS" or . == "QUEUED" or . == "EXPECTED")) then "PENDING"
                 else "GREEN" end) as $checks
              | (if .isDraft then " | DRAFT" else "" end) as $draft
              | (if ((.reviewDecision // "") == "") then "none" else .reviewDecision end) as $rev
              | "- #\(.number) \(.url)\n    title:  \(.title)\n    branch: \(.baseRefName) ← \(.headRefName)\n    checks: \($checks) | mergeState: \(.mergeStateStatus) | review: \($rev)\($draft) | updated: \(.updatedAt)"
              ' 2>/dev/null)
    if [[ -z "$out" ]]; then
        # retry without the fancy jq in case a field is unsupported on this gh version
        out=$(gh pr list --repo "$ghrepo" --state open --limit 60 \
            --json number,title,url,headRefName,isDraft \
            --jq '.[] | "- #\(.number) \(.url)\n    title:  \(.title)\n    branch: \(.headRefName)\(if .isDraft then " [DRAFT]" else "" end)"' 2>/dev/null)
    fi
    if [[ -z "$out" ]]; then echo "  (none open, or gh query failed)"; else echo "$out"; fi
}

cmd_prs() {
    echo "## Open PRs — every one carries its merge URL (never a bare #number)"
    echo
    local row
    for row in "${REPOS[@]}"; do
        IFS='|' read -r key ghrepo base path <<< "$row"
        echo "### $key  (base: $base)"
        pr_lines_for_repo "$key" "$ghrepo" "$base"
        echo
    done
    cat <<'EOF'
> ⚠️ `mergeState: UNKNOWN` means GitHub had not computed mergeability at query time — it is NOT
> "mergeable". `checks:` here is the list-query rollup and can disagree with the live gate.
> **Before presenting ANY PR as a merge step, verify live:** `gh pr checks <n> --repo <repo>`
> all green AND zero unresolved review threads (thread query: /shipit Step 5b).
> Merges are Mike's. Hand him the command — always `--merge`, never `--squash`.
EOF
}

# ---------------------------------------------------------------- list

cmd_list() {
    echo "## Known projects"
    echo
    local active=""
    [[ -f "$PM_DIR/.active-project" ]] && active=$(tr -d '[:space:]' < "$PM_DIR/.active-project")
    echo "PM active project (global — NOT necessarily this window): ${active:-<none set>}"
    # THIS window's own project, if it has a record — the honest per-window answer.
    if command -v wc_resolve_project >/dev/null 2>&1; then
        local wproj; wproj=$(wc_resolve_project 2>/dev/null || echo "")
        echo "This window's project: ${wproj:-<no record — run /letsbuild or /handoff to register>}"
    fi
    echo
    echo "### /pm projects (full artifacts)"
    local d
    for d in "$PM_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local base; base=$(basename "$d")
        [[ "$base" == "archive" ]] && continue
        local mark=""; [[ "$base" == "$active" ]] && mark="  ← PM-ACTIVE"
        local chunks="?" upd="?"
        # Briefs are generated one-per-chunk by /pm init — the accurate count.
        if compgen -G "$d/briefs/*.md" >/dev/null 2>&1; then
            chunks=$(ls "$d"/briefs/*.md 2>/dev/null | wc -l | tr -d '[:space:]')
        elif [[ -f "$d/status.md" ]]; then
            # Fallback: count table DATA rows by exclusion. Chunk IDs vary wildly across
            # projects (P1, **S**, A, FF5, WS5a), so match table shape, not ID shape.
            chunks=$(grep -E '^\|' "$d/status.md" 2>/dev/null \
                | grep -vE '^\|[[:space:]:|-]+\|?[[:space:]]*$' \
                | grep -viE '^\|[[:space:]]*\**(chunk|id|track)\b' \
                | wc -l | tr -d '[:space:]')
        fi
        [[ -f "$d/status.md" ]] && upd=$(date -r "$d/status.md" +%Y-%m-%d 2>/dev/null || echo "?")
        echo "- $base — ${chunks:-0} chunks, status.md updated ${upd}$mark"
    done
    echo
    echo "### archived"
    ls "$PM_DIR/archive" 2>/dev/null | sed 's/^/- /' || echo "(none)"
    echo
    echo "### live windows (from ~/.claude/windows — who is on what right now)"
    if command -v wc_list >/dev/null 2>&1; then
        # anchor \t role \t project \t chunk \t branch \t worktree \t live|stale
        wc_list 2>/dev/null | awk -F'\t' '$7=="live"{printf "- %s (%s) %s%s — %s\n",$3,$2,($4!="-"?"["$4"] ":""),$5,$6}' \
            || echo "  (none registered)"
    else
        echo "  (window-context.sh not deployed)"
    fi
    echo
    echo "### memory-tracked workstreams (no /pm dir — see MEMORY.md index)"
    echo "  $MEM_DIR/MEMORY.md"
}

# ---------------------------------------------------------------- gather

cmd_gather() {
    local q="${1:-}"
    local dir; dir=$(resolve_project "$q")
    local rc=$?

    # THIS window has no project record and none could be inferred — REFUSE, don't guess.
    if [[ $rc -eq 3 || "$dir" == "NO_WINDOW_CONTEXT" ]]; then
        echo "## THIS WINDOW HAS NO REGISTERED PROJECT — refusing to guess"
        echo
        echo "No per-window record binds this window (its claude process) to a project, and no"
        echo "unique live window matches this branch/cwd. Reporting the machine-global"
        echo "\`~/.claude/pm/.active-project\` here would be a guess — and reporting the WRONG"
        echo "project is exactly the defect this resolver fixes. So: pick explicitly."
        echo
        echo "### Live windows you might mean (from ~/.claude/windows)"
        if command -v wc_list >/dev/null 2>&1; then
            wc_list 2>/dev/null | awk -F'\t' '$7=="live"{printf "  - %s (%s) %s%s\n",$3,$2,($4!="-"?"["$4"] ":""),$5}' \
                || echo "  (none registered — nothing has written a window record yet)"
            local anylive; anylive=$(wc_list 2>/dev/null | awk -F'\t' '$7=="live"' | wc -l | tr -d ' ')
            [[ "${anylive:-0}" -eq 0 ]] && echo "  (none registered — nothing has written a window record yet)"
        else
            echo "  (window-context.sh not deployed — cannot list windows)"
        fi
        echo
        echo "### To fix it for THIS window"
        echo "  - Run \`/letsbuild\` (registers the window), or \`/handoff\` (checkpoints + registers), OR"
        echo "  - Ask by name:  \`/sitrep <project>\`   (e.g. /sitrep vouchers, /sitrep w114)"
        echo
        echo "### All known projects (if you meant one of these)"
        cmd_list | sed -n '/### \/pm projects/,/^$/p'
        exit 3
    fi

    if [[ $rc -eq 2 ]]; then
        echo "AMBIGUOUS — \"$q\" matches several projects. Ask Mike which:"
        resolve_project "$q" | tail -n +2 | sed 's/^/  - /'
        exit 2
    fi

    # -- THIS window's own record: the CHEAP situation. When /sitrep runs for the current
    #    window (no name arg), its record already carries phase/next/pr/feature written at
    #    the moment the window knew them — lead the recap with THIS instead of re-deriving the
    #    whole situation from the raw artifacts below (that re-derivation is the token cost).
    if [[ -z "$q" ]] && command -v wc_read >/dev/null 2>&1; then
        local wrec; wrec=$(wc_read 2>/dev/null)
        if [[ -n "$wrec" ]]; then
            echo "## THIS WINDOW's live record — lead the recap with this (no re-derivation needed)"
            echo
            printf '%s\n' "$wrec" | sed 's/^/    /'
            echo
            echo "  (phase/next/pr here are what the window last recorded; still verify PRs live below.)"
            echo
        fi
    fi

    if [[ $rc -ne 0 || "$dir" == "NONE" ]]; then
        echo "## No /pm project matched \"${q:-<this window>}\" — NON-PM MODE"
        echo
        echo "This workstream has no ~/.claude/pm dir. Build the sitrep from the window record"
        echo "above (if any) + memory + live git/gh."
        echo
        # Memory needs a slug. With an explicit name use it; for the no-arg current-window
        # case fall back to the window's own project so a solo/memory-tracked window still
        # gets its memory hits (resolve_project returned NONE, dropping the slug).
        local mslug="$q"
        if [[ -z "$mslug" ]] && command -v wc_resolve_project >/dev/null 2>&1; then
            mslug=$(wc_resolve_project 2>/dev/null || echo "")
        fi
        if [[ -n "$mslug" ]]; then
            echo "### Memory hits for \"$mslug\""
            memory_hits "$mslug"
            echo
        fi
        echo "### Memory index (find the workstream line here)"
        echo "  $MEM_DIR/MEMORY.md"
        echo
        cmd_prs
        echo
        echo "### Available /pm projects (if Mike meant one of these)"
        cmd_list | sed -n '/### \/pm projects/,/^$/p'
        return 0
    fi

    local proj; proj=$(basename "$dir")
    echo "# SITREP FACTS — $proj"
    echo "# Gathered: $(date -u +%Y-%m-%dT%H:%M:%SZ)  |  Project dir: $dir"
    echo
    echo "> These are FACTS ONLY. Write the reply in the canonical shape:"
    echo ">   ~/.claude/skills/sitrep/FORMAT.md  (recap → numbered paste-order steps)"
    echo "> Analysis stays in the artifacts below and is referenced BY PATH, never pasted."
    echo

    # -- master plan: the WHAT (for the recap)
    if [[ -f "$dir/master-plan.md" ]]; then
        echo "## Master plan (head — source of the recap's 'what this is')"
        echo
        head -30 "$dir/master-plan.md"
        echo
        echo "  (full: $dir/master-plan.md)"
        echo
    fi

    # -- status: the WHERE WE ARE
    if [[ -f "$dir/status.md" ]]; then
        echo "## status.md — chunk state (the 'where we are')"
        echo
        cat "$dir/status.md"
        echo
    fi

    # -- roster: WHO is running (the 'in flight')
    if [[ -f "$dir/roster.md" ]]; then
        echo "## roster.md — active windows ('in flight'; if empty, SAY SO — it's a finding)"
        echo
        cat "$dir/roster.md"
        echo
    fi

    if [[ -f "$dir/roster-events.jsonl" ]]; then
        echo "## Recent events (last 12 — the event key is \`event\`, NOT \`type\`)"
        echo
        # jq, not grep: these rows carry free-text notes with quotes and braces that
        # regex-scraping mangles. Fall back to raw lines if jq is unavailable.
        if command -v jq >/dev/null 2>&1; then
            tail -12 "$dir/roster-events.jsonl" 2>/dev/null | jq -r '
                # .pr is polymorphic across events: number (1574), qualified string
                # ("org/repo#1299"), or an array of either. Render each shape correctly.
                def prfmt: if type == "array" then (map(tostring) | join(", "))
                           elif type == "number" then "#\(.)"
                           else tostring end;
                # timestamp key is `ts` on most rows, `date` on ~194 others (both used).
                "- `\(.ts // .date // "?")` \(.event // "?")"
                + " | window=\(.window // "-")"
                + " | chunk=\(.chunk // "-")"
                + (if .pr      then " | pr=\(.pr | prfmt)"  else "" end)
                + (if .verdict then " | verdict=\(.verdict)" else "" end)
                + (if .note    then "\n    note: \(.note | .[0:220])" else "" end)
            ' 2>/dev/null || tail -12 "$dir/roster-events.jsonl"
        else
            tail -12 "$dir/roster-events.jsonl"
        fi
        echo
    fi

    # -- decisions: things WAITING ON MIKE become steps
    if [[ -d "$dir/decisions" ]] && compgen -G "$dir/decisions/*.md" >/dev/null; then
        echo "## Decisions — UNANSWERED ones are candidate next steps"
        echo
        local f
        for f in "$dir/decisions"/*.md; do
            [[ -f "$f" ]] || continue
            if grep -qE '^\s*(\*\*)?Decision(\*\*)?:\s*\S' "$f" 2>/dev/null; then
                echo "- ANSWERED  $f"
            else
                echo "- ⏳ OPEN    $f   ← needs Mike"
            fi
        done
        echo
    fi

    # -- briefs available (steps often = "launch dev-X on chunk-Y")
    if [[ -d "$dir/briefs" ]] && compgen -G "$dir/briefs/*.md" >/dev/null; then
        echo "## Briefs on disk (a step is a POINTER to one of these, never its body)"
        echo
        ls "$dir/briefs"/*.md 2>/dev/null | sed 's|^|- |'
        echo
    fi

    # -- reviews/reports: reference BY PATH, never paste
    local sect
    for sect in reviews reports; do
        if [[ -d "$dir/$sect" ]] && compgen -G "$dir/$sect/*.md" >/dev/null; then
            echo "## $sect/ — reference BY PATH in the reply; do NOT paste contents"
            echo
            ls -t "$dir/$sect"/*.md 2>/dev/null | sed 's|^|- |'
            echo
        fi
    done

    if [[ -f "$dir/acceptance-log.md" ]]; then
        echo "## Acceptance log: $dir/acceptance-log.md"
        echo
    fi

    # -- PRs this project already references
    if [[ -f "$dir/status.md" ]]; then
        local refs
        refs=$(grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' "$dir/status.md" 2>/dev/null | sort -u)
        if [[ -n "$refs" ]]; then
            echo "## PRs referenced in status.md"
            echo
            echo "$refs" | sed 's|^|- |'
            echo
        fi
    fi

    # -- memory
    echo "## Memory hits for \"$proj\""
    echo
    memory_hits "$proj"
    echo

    # -- live PRs everywhere
    cmd_prs
}

# ---------------------------------------------------------------- main

case "${1:-gather}" in
    gather)  shift; cmd_gather "${1:-}" ;;
    list)    cmd_list ;;
    prs)     cmd_prs ;;
    resolve) shift; resolve_project "${1:-}" ;;
    *)       echo "Usage: $0 {gather [project] | list | prs | resolve <name>}" >&2; exit 1 ;;
esac
