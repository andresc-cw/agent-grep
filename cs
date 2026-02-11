#!/usr/bin/env bash
set -euo pipefail

# cs — search Claude Code & Codex sessions, pick one with fzf, resume it
#
# Usage:
#   cs <search terms>          Search sessions and pick one to resume
#   cs --list                  Browse all sessions (no search filter)
#   cs --update                Re-index sessions before searching

SESSION_DIR="$HOME/.cache/claude-search/sessions"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Helpers ─────────────────────────────────────────────────────────────

# Read frontmatter from a markdown file and emit a tab-separated fzf line:
#   session_id \t agent \t project_path \t [agent] project  date  slug
format_md() {
    local mdfile="$1"
    local fname agent sid project project_name date slug short_date display_name
    fname=$(basename "$mdfile" .md)

    # Extract agent + id from filename: claude-<uuid> or codex-<uuid>
    agent="${fname%%-*}"
    sid="${fname#*-}"

    # Read frontmatter
    project=$(sed -n 's/^project: *//p' "$mdfile" | head -1)
    project_name=$(sed -n 's/^project_name: *//p' "$mdfile" | head -1)
    date=$(sed -n 's/^date: *//p' "$mdfile" | head -1)
    slug=$(sed -n 's/^slug: *//p' "$mdfile" | head -1)

    short_date="${date:0:10}"

    if [[ "$agent" == "claude" && -n "${slug:-}" && "$slug" != "untitled" ]]; then
        display_name="$slug"
    else
        display_name="${sid:0:12}..."
    fi

    printf '%s\t%s\t%s\t[%s] %-20s %s  %s\n' \
        "$sid" "$agent" "${project:-}" "$agent" "${project_name:-unknown}" "${short_date:-????-??-??}" "$display_name"
}

run_fzf() {
    fzf --delimiter=$'\t' \
        --with-nth=4 \
        --preview="head -40 $SESSION_DIR/{2}-{1}.md" \
        --preview-window=right:50%:wrap \
        --header="Select a session to resume (Enter=open, Esc=cancel)" \
        --no-sort
}

# ── Handle flags ────────────────────────────────────────────────────────

if [[ "${1:-}" == "--update" ]]; then
    "$SCRIPT_DIR/session2md.sh"
    shift
    [[ $# -eq 0 ]] && exit 0
fi

LIST_MODE=""
if [[ "${1:-}" == "--list" ]]; then
    LIST_MODE=1
fi

if [[ -z "$LIST_MODE" ]]; then
    query="$*"
    [[ -z "$query" ]] && { echo "Usage: cs <search terms>"; echo "       cs --list"; echo "       cs --update [search terms]"; exit 1; }
fi

# ── Build fzf input ────────────────────────────────────────────────────

if [[ -n "$LIST_MODE" ]]; then
    # List all sessions directly from markdown files (sorted newest first)
    selected=$(
        for mdfile in $(ls -t "$SESSION_DIR"/*.md 2>/dev/null); do
            format_md "$mdfile"
        done | run_fzf
    )
else
    # Search via qmd
    results=$(qmd search "$query" -c sessions --json -n 20 2>/dev/null)

    if [[ -z "$results" || "$results" == "[]" ]]; then
        echo "No sessions found for: $query"
        exit 1
    fi

    selected=$(echo "$results" | jq -r '.[] | .file' | while IFS= read -r filepath; do
        mdfile="$SESSION_DIR/$(basename "$filepath")"
        [[ -f "$mdfile" ]] && format_md "$mdfile"
    done | run_fzf)
fi

[[ -z "$selected" ]] && exit 0

# ── Extract and resume ──────────────────────────────────────────────────

session_id=$(echo "$selected" | cut -f1)
agent=$(echo "$selected" | cut -f2)
project_dir=$(echo "$selected" | cut -f3)

# claude --resume is project-scoped: it only finds sessions for the cwd's project
if [[ -n "$project_dir" && -d "$project_dir" ]]; then
    cd "$project_dir"
fi

if [[ "$agent" == "claude" ]]; then
    exec claude --resume "$session_id"
else
    exec codex --resume "$session_id"
fi
