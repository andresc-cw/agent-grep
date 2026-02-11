# agent-grep

Search and resume your Claude Code and Codex sessions from the terminal.

`cs` converts your JSONL session files into searchable markdown, indexes them with [qmd](https://github.com/acrucetta/qmd), and lets you fuzzy-find and resume any session with `fzf`.

## How it works

1. **`session2md.sh`** — Reads Claude Code (`~/.claude/projects/`) and Codex (`~/.codex/sessions/`) JSONL files, converts them to markdown with frontmatter (session ID, project, date, slug), and stores them in `~/.cache/claude-search/sessions/`.

2. **`cs`** — Searches the indexed sessions via `qmd`, presents results in `fzf` with preview, and resumes the selected session with `claude --resume` or `codex --resume`.

3. **`com.claude-search.session2md.plist`** — macOS LaunchAgent that runs `session2md.sh` every 5 minutes to keep the index fresh.

## Usage

```bash
cs <search terms>    # Search sessions and pick one to resume
cs --list            # Browse all sessions
cs --update          # Re-index sessions before searching
```

## Prerequisites

- [qmd](https://github.com/acrucetta/qmd) — local markdown search
- [fzf](https://github.com/junegunn/fzf) — fuzzy finder
- [jq](https://github.com/jqlang/jq) — JSON processing
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and/or [Codex](https://github.com/openai/codex)

## Install

```bash
# Clone the repo
git clone https://github.com/andresc-cw/agent-grep.git
cd agent-grep

# Add cs to your PATH (e.g., symlink it)
ln -s "$(pwd)/cs" ~/.local/bin/cs

# (Optional) Install the LaunchAgent for automatic indexing
cp com.claude-search.session2md.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.claude-search.session2md.plist
```

## Manual indexing

```bash
# Convert sessions and index
./session2md.sh

# See stats without converting

./session2md.sh --stats

# Force re-convert all sessions
./session2md.sh --full
```
