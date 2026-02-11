#!/usr/bin/env bash
set -euo pipefail

# cs — search Claude Code & Codex sessions, pick one with fzf, resume it
#
# Usage:
#   cs <search terms>          Search and pick a session to resume
#   cs --list                  Browse all sessions (no search filter)
#   cs --update                Re-index sessions before searching

SESSION_DIR="$HOME/.cache/claude-search/sessions"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Handle flags ────────────────────────────────────────────────────────

if [[ "${1:-}" == "--update" ]]; then
    "$SCRIPT_DIR/session2md.sh"
    qmd update 2>&1
    shift
    [[ $# -eq 0 ]] && exit 0
fi

if [[ "${1:-}" == "--list" ]]; then
    # Browse all sessions without a search query
    query="*"
    search_args=(-c sessions --json -n 50 --all)
else
    query="$*"
    [[ -z "$query" ]] && { echo "Usage: cs <search terms>"; echo "       cs --list"; echo "       cs --update [search terms]"; exit 1; }
    search_args=(-c sessions --json -n 20)
fi

# ── Search via qmd ──────────────────────────────────────────────────────

results=$(qmd search "$query" "${search_args[@]}" 2>/dev/null)

if [[ -z "$results" || "$results" == "[]" ]]; then
    echo "No sessions found for: $query"
    exit 1
fi

# ── Format results for fzf ──────────────────────────────────────────────
#
# We parse qmd JSON and read frontmatter from each matched .md file to get:
#   agent, session_id, project_name, date, slug
#
# fzf display format:
#   [claude] project_name  2026-02-10  slug-name
#     "...snippet..."

selected=$(echo "$results" | jq -r '
    .[] |
    # Extract agent and session_id from filename
    (.file | capture("(?<agent>claude|codex)-(?<id>[^.]+)\\.md$")) as $info |
    # Output: filepath \t agent \t id \t title \t snippet
    "\(.file)\t\($info.agent)\t\($info.id)\t\(.title // "untitled")\t\(.snippet // "" | gsub("\n"; " ") | .[0:200])"
' | while IFS=$'\t' read -r filepath agent sid title snippet; do
    # Resolve the actual file path from qmd://sessions/... format
    mdfile="$SESSION_DIR/$(basename "$filepath")"

    # Extract frontmatter fields
    if [[ -f "$mdfile" ]]; then
        project_name=$(sed -n 's/^project_name: *//p' "$mdfile" | head -1)
        date=$(sed -n 's/^date: *//p' "$mdfile" | head -1)
        slug=$(sed -n 's/^slug: *//p' "$mdfile" | head -1)
    fi

    # Format date to just YYYY-MM-DD
    short_date="${date:0:10}"

    # Display name: prefer slug for claude, session id prefix for codex
    if [[ "$agent" == "claude" && -n "${slug:-}" && "$slug" != "untitled" ]]; then
        display_name="$slug"
    else
        display_name="${sid:0:12}..."
    fi

    # Output tab-separated: session_id \t agent \t display line
    printf '%s\t%s\t[%s] %-20s %s  %s\n' \
        "$sid" "$agent" "$agent" "${project_name:-unknown}" "${short_date:-????-??-??}" "$display_name"
done | fzf --delimiter=$'\t' \
           --with-nth=3 \
           --preview="head -40 $SESSION_DIR/{2}-{1}.md" \
           --preview-window=right:50%:wrap \
           --header="Select a session to resume (Enter=open, Esc=cancel)" \
           --no-sort)

[[ -z "$selected" ]] && exit 0

# ── Extract and resume ──────────────────────────────────────────────────

session_id=$(echo "$selected" | cut -f1)
agent=$(echo "$selected" | cut -f2)

if [[ "$agent" == "claude" ]]; then
    exec claude --resume "$session_id"
else
    exec codex --resume "$session_id"
fi
