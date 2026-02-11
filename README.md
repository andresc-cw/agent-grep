# agent-grep

Search and resume your Claude Code and Codex sessions from the terminal.

Type a few words about what you discussed, pick the session from a list, and you're back in it.

## Usage

```bash
sg "billing bug"    # search session content, pick one, resume it
sg --list           # browse all sessions, type to filter by content
sg --update         # re-index before searching
```

## Architecture

```
~/.claude/projects/**/*.jsonl ─┐
                               ├── session2md.sh ──► ~/.cache/agent-grep/sessions/*.md
~/.codex/sessions/**/*.jsonl ──┘       (jq)                     │
                                                                │
                       launchd runs session2md.sh          qmd collection
                       every 5 min to keep fresh           (BM25 index)
                                                                │
                ┌───────────────────────────────────────────────┘
                │
          sg<query>                          sg--list
                │                                  │
                ▼                                  ▼
       rg: find sessions                  gawk: read all
       containing query                   frontmatters
                │                                  │
                └──────────┬───────────────────────┘
                           ▼
                    ┌─────────────┐
                    │     fzf     │
                    │             │
                    │  type ──► rg+gawk   (live content search)
                    │  preview ──► head    (session preview)
                    │             │
                    └──────┬──────┘
                           │ Enter
                           ▼
                     cd <project dir>
                     claude --resume <id>
                     (or codex --resume)
```

Each JSONL session is converted to a markdown file with YAML frontmatter (session ID, project, date, slug) and the full conversation text. The markdown files serve as the search corpus for both `qmd` (ranked search) and `rg` (live content filtering).

## Performance

Benchmarked on 610 sessions (496 Claude Code + 114 Codex), 6.2 MB total on an M1 Mac.

| Operation | Time | How |
|-----------|------|-----|
| **List all 610 sessions** | **0.16s** | Single `gawk` pass reads all frontmatters |
| **Content search (broad, 342 hits)** | **0.14s** | `rg` parallel grep + `gawk` format |
| **Content search (narrow, 5 hits)** | **0.06s** | `rg` + `gawk` on few files |
| **Incremental re-index (2 changed)** | **~1s** | `session2md.sh` skips unchanged files |
| **Full re-index (610 sessions)** | **~45s** | One-time `jq` conversion of all JSONL |

Live content search runs on every keystroke via fzf's `--disabled` + `change:reload`, backed by ripgrep's parallel I/O. Feels instant.

## Install

```bash
# 1. Dependencies
brew install jq fzf gawk ripgrep
bun install -g github:tobi/qmd

# 2. Clone and symlink
git clone https://github.com/andresc-cw/agent-grep.git
cd agent-grep
ln -s "$(pwd)/sg" ~/.local/bin/sg

# 3. Initial index
./session2md.sh                                              # convert sessions
qmd collection add ~/.cache/agent-grep/sessions --name sessions  # build search index

# 4. (Optional) Auto-index every 5 minutes
cp com.agent-grep.session2md.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.agent-grep.session2md.plist
```

## Dependencies

| Tool | Purpose | Install |
|------|---------|---------|
| [qmd](https://github.com/tobi/qmd) | Markdown search engine (BM25 index) | `bun install -g github:tobi/qmd` |
| [fzf](https://github.com/junegunn/fzf) | Interactive picker with preview | `brew install fzf` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Fast parallel content search | `brew install ripgrep` |
| [gawk](https://www.gnu.org/software/gawk/) | Frontmatter parsing (needs `ENDFILE`) | `brew install gawk` |
| [jq](https://github.com/jqlang/jq) | JSONL to markdown conversion | `brew install jq` |

## Manual indexing

```bash
./session2md.sh           # incremental convert (skips unchanged)
./session2md.sh --full    # force re-convert everything
./session2md.sh --stats   # show session counts without converting
```

## Files

| File | Purpose |
|------|---------|
| `sg` | Search + fzf picker + auto-resume |
| `session2md.sh` | JSONL to markdown converter (bash + jq) |
| `.sg_fmt.awk` | gawk program for fast frontmatter extraction |
| `com.agent-grep.session2md.plist` | launchd plist for background indexing |
