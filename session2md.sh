#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="$HOME/.cache/agent-grep/sessions"
CLAUDE_DIR="$HOME/.claude/projects"
CODEX_DIR="$HOME/.codex/sessions"
FTS_DB="$HOME/.cache/agent-grep/sessions.sqlite"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FTS_FMT="$SCRIPT_DIR/.sg_idx.awk"

FULL=""
STATS_ONLY=""

for arg in "$@"; do
    case "$arg" in
        --full)  FULL=1 ;;
        --stats) STATS_ONLY=1 ;;
        *)       echo "Usage: session2md.sh [--full] [--stats]"; exit 1 ;;
    esac
done

mkdir -p "$OUT_DIR"

# Counters
claude_total=0; claude_converted=0; claude_skipped=0
codex_total=0;  codex_converted=0;  codex_skipped=0

# SQL single-quote escaping for sqlite string literals.
sql_quote() {
    printf "%s" "$1" | sed "s/'/''/g"
}

rebuild_fts_index() {
    command -v sqlite3 >/dev/null 2>&1 || return 0
    [[ -f "$FTS_FMT" ]] || return 0

    local files=()
    shopt -s nullglob
    files=("$OUT_DIR"/*.md)
    shopt -u nullglob

    if [[ ${#files[@]} -eq 0 ]]; then
        rm -f "$FTS_DB"
        return 0
    fi

    local tmp_db="${FTS_DB}.tmp"
    local sql_file="${FTS_DB}.sql"
    rm -f "$tmp_db" "$sql_file"

    {
        cat <<'SQL'
PRAGMA journal_mode=OFF;
PRAGMA synchronous=OFF;
PRAGMA temp_store=MEMORY;
CREATE VIRTUAL TABLE sessions_fts USING fts5(
    path UNINDEXED,
    session_id UNINDEXED,
    agent UNINDEXED,
    project UNINDEXED,
    project_name,
    date UNINDEXED,
    slug,
    body,
    tokenize='unicode61 remove_diacritics 2 tokenchars ''-_''',
    prefix='2 3 4'
);
BEGIN;
SQL

        gawk -f "$FTS_FMT" "${files[@]}" | while IFS=$'\t' read -r path sid agent project pname date slug; do
            local q_path q_sid q_agent q_project q_pname q_date q_slug
            q_path=$(sql_quote "$path")
            q_sid=$(sql_quote "$sid")
            q_agent=$(sql_quote "$agent")
            q_project=$(sql_quote "$project")
            q_pname=$(sql_quote "$pname")
            q_date=$(sql_quote "$date")
            q_slug=$(sql_quote "$slug")

            printf "INSERT INTO sessions_fts(path,session_id,agent,project,project_name,date,slug,body) "
            printf "VALUES('%s','%s','%s','%s','%s','%s','%s',CAST(readfile('%s') AS TEXT));\n" \
                "$q_path" "$q_sid" "$q_agent" "$q_project" "$q_pname" "$q_date" "$q_slug" "$q_path"
        done

        echo "COMMIT;"
    } > "$sql_file"

    if sqlite3 "$tmp_db" < "$sql_file" >/dev/null 2>&1; then
        mv "$tmp_db" "$FTS_DB"
        echo "FTS:   indexed ${#files[@]} sessions"
    fi

    rm -f "$tmp_db" "$sql_file"
}

# ── Claude Code conversion ──────────────────────────────────────────────

convert_claude() {
    local file="$1" id="$2"

    # Extract metadata from the first user or assistant line
    local meta
    meta=$(jq -r '
        select(.type == "user" or .type == "assistant") |
        {sessionId, slug, timestamp, cwd} | @json
    ' "$file" | head -1)

    local session_id slug date cwd project
    session_id=$(echo "$meta" | jq -r '.sessionId // empty')
    slug=$(echo "$meta" | jq -r '.slug // empty')
    date=$(echo "$meta" | jq -r '.timestamp // empty')
    cwd=$(echo "$meta" | jq -r '.cwd // empty')
    project="${cwd##*/}"

    # Frontmatter
    cat <<EOF
---
session_id: ${session_id:-$id}
agent: claude
project: ${cwd:-unknown}
project_name: ${project:-unknown}
date: ${date:-unknown}
slug: ${slug:-untitled}
resume: claude --resume ${session_id:-$id}
---

# ${slug:-$id}

EOF

    # Extract conversation text: user/assistant text blocks + tool use summaries
    # Note: .message.content can be a string or an array depending on the message
    jq -r '
        select(.type == "user" or .type == "assistant") |
        (.type | if . == "user" then "**User:**" else "**Assistant:**" end) as $role |
        (if (.message.content | type) == "string" then
            .message.content
        else
            [.message.content[] |
                if .type == "text" then .text
                elif .type == "tool_use" then
                    "[Tool: \(.name)]" +
                    (if .input.description then " " + .input.description
                     elif .input.command then " `" + (.input.command | split("\n") | .[0]) + "`"
                     elif .input.query then " " + .input.query
                     elif .input.pattern then " " + .input.pattern
                     elif .input.file_path then " " + .input.file_path
                     else ""
                     end)
                else empty
                end
            ] | join("\n")
        end) |
        if . != "" then $role + " " + . else empty end
    ' "$file"
}

# ── Codex conversion ────────────────────────────────────────────────────

convert_codex() {
    local file="$1" id="$2"

    # Extract metadata from session_meta line
    local meta
    meta=$(jq -r 'select(.type == "session_meta") | .payload | @json' "$file" | head -1)

    local cwd project date
    cwd=$(echo "$meta" | jq -r '.cwd // empty')
    project="${cwd##*/}"
    date=$(echo "$meta" | jq -r '.timestamp // empty')

    # Frontmatter
    cat <<EOF
---
session_id: ${id}
agent: codex
project: ${cwd:-unknown}
project_name: ${project:-unknown}
date: ${date:-unknown}
resume: codex resume ${id}
---

# codex-${id}

EOF

    # Extract conversation from event_msg (user_message + agent_message)
    # These are the cleanest source — response_items duplicate the same content
    jq -r '
        if .type == "event_msg" and .payload.type == "user_message" then
            "**User:** " + .payload.message
        elif .type == "event_msg" and .payload.type == "agent_message" then
            "**Assistant:** " + .payload.message
        else empty end
    ' "$file"
}

# ── Main loop ───────────────────────────────────────────────────────────

# Process Claude Code sessions (skip subagent files)
if [[ -d "$CLAUDE_DIR" ]]; then
    while IFS= read -r f; do
        claude_total=$((claude_total + 1))
        id=$(basename "$f" .jsonl)
        out="$OUT_DIR/claude-${id}.md"

        if [[ -z "$STATS_ONLY" ]]; then
            if [[ -z "$FULL" && -f "$out" && "$out" -nt "$f" ]]; then
                claude_skipped=$((claude_skipped + 1))
                continue
            fi
            convert_claude "$f" "$id" > "$out" 2>/dev/null || rm -f "$out"
            if [[ -f "$out" ]]; then
                claude_converted=$((claude_converted + 1))
            fi
        fi
    done < <(find "$CLAUDE_DIR" -maxdepth 2 -name "*.jsonl" -type f)
fi

# Process Codex sessions
if [[ -d "$CODEX_DIR" ]]; then
    while IFS= read -r f; do
        codex_total=$((codex_total + 1))

        # Extract session ID from filename (it's the UUID portion after the timestamp)
        local_id=$(basename "$f" .jsonl | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' || true)
        if [[ -z "$local_id" ]]; then
            # Fallback: try to get ID from session_meta
            local_id=$(jq -r 'select(.type == "session_meta") | .payload.id' "$f" 2>/dev/null | head -1)
        fi
        [[ -z "$local_id" || "$local_id" == "null" ]] && continue

        out="$OUT_DIR/codex-${local_id}.md"

        if [[ -z "$STATS_ONLY" ]]; then
            if [[ -z "$FULL" && -f "$out" && "$out" -nt "$f" ]]; then
                codex_skipped=$((codex_skipped + 1))
                continue
            fi
            convert_codex "$f" "$local_id" > "$out" 2>/dev/null || rm -f "$out"
            if [[ -f "$out" ]]; then
                codex_converted=$((codex_converted + 1))
            fi
        fi
    done < <(find "$CODEX_DIR" -name "*.jsonl" -type f)
fi

# ── Summary ─────────────────────────────────────────────────────────────

if [[ -n "$STATS_ONLY" ]]; then
    echo "Claude Code sessions: $claude_total"
    echo "Codex sessions:       $codex_total"
    echo "Total:                $((claude_total + codex_total))"
    existing=$(find "$OUT_DIR" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    echo "Indexed (existing):   $existing"
else
    echo "Claude: ${claude_converted} converted, ${claude_skipped} skipped (${claude_total} total)"
    echo "Codex:  ${codex_converted} converted, ${codex_skipped} skipped (${codex_total} total)"

    if command -v sqlite3 >/dev/null 2>&1 && [[ -f "$FTS_FMT" ]]; then
        needs_fts=0
        if [[ $((claude_converted + codex_converted)) -gt 0 ]]; then
            needs_fts=1
        elif [[ ! -f "$FTS_DB" ]]; then
            needs_fts=1
        elif ! sqlite3 "$FTS_DB" "SELECT 1 FROM sessions_fts LIMIT 1;" >/dev/null 2>&1; then
            needs_fts=1
        else
            md_count=$(find "$OUT_DIR" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
            db_count=$(sqlite3 "$FTS_DB" "SELECT count(*) FROM sessions_fts;" 2>/dev/null || echo "")
            [[ "$md_count" != "$db_count" ]] && needs_fts=1
        fi

        [[ "$needs_fts" -eq 1 ]] && rebuild_fts_index
    fi
fi
