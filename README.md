# agent-grep

Search and resume your Claude Code and Codex sessions from the terminal.

`cs` converts your JSONL session files into searchable markdown, indexes them with [qmd](https://github.com/tobi/qmd), and lets you search session **content** and resume any session with `fzf`.

## How it works

1. **`session2md.sh`** — Reads Claude Code (`~/.claude/projects/`) and Codex (`~/.codex/sessions/`) JSONL files, converts them to markdown with frontmatter (session ID, project, date, slug), and stores them in `~/.cache/claude-search/sessions/`.

2. **`cs`** — Searches session content with `rg` (ripgrep), presents results in `fzf` with live content filtering and preview, and resumes the selected session with `claude --resume` or `codex --resume`.

3. **`com.claude-search.session2md.plist`** — macOS LaunchAgent that runs `session2md.sh` every 5 minutes to keep the index fresh.

## Usage

```bash
cs <search terms>    # Search session content and pick one to resume
cs --list            # Browse all sessions, type to search content live
cs --update          # Re-index sessions before searching
```

## Prerequisites

```bash
brew install jq fzf gawk ripgrep
bun install -g github:tobi/qmd
```

- [qmd](https://github.com/tobi/qmd) — local markdown search engine (indexes sessions)
- [fzf](https://github.com/junegunn/fzf) — fuzzy finder (interactive picker)
- [ripgrep](https://github.com/BurntSushi/ripgrep) — fast content search (live filtering)
- [gawk](https://www.gnu.org/software/gawk/) — GNU awk (macOS awk lacks `ENDFILE`)
- [jq](https://github.com/jqlang/jq) — JSON processing (JSONL conversion)
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
