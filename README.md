# agent-grep

Search and resume your Claude Code and Codex sessions from the terminal.

Type a few words about what you discussed, pick the session from a list, and you're back in it.

## Usage

```bash
sg "billing bug"    # search session content, pick one, resume it
sg --list           # browse all sessions, type to filter by content
sg --repo billing   # browse/search sessions scoped to one repo/project
sg --sort-date      # start with date-desc sorting enabled
sg --update         # re-index before searching
```

Inside the picker, press `Alt-d` to toggle date sorting on/off.

## Architecture

```
~/.claude/projects/**/*.jsonl ─┐
                               ├── session2md.sh ──► ~/.cache/agent-grep/sessions/*.md
~/.codex/sessions/**/*.jsonl ──┘       (jq)                     │
                                                                │
                       launchd runs session2md.sh
                       every 5 min to keep fresh
                                │
                ┌───────────────┘
                │
          sg<query>                          sg--list
                │                                  │
                ▼                                  ▼
sqlite fts5 rank (fallback rg)            gawk: read all
       matching sessions                   frontmatters
                │                                  │
                └──────────┬───────────────────────┘
                           ▼
                    ┌─────────────┐
                    │     fzf     │
                    │             │
                    │  type ──► fts5+gawk (fallback rg)
                    │  preview ──► head    (session preview)
                    │             │
                    └──────┬──────┘
                           │ Enter
                           ▼
                     cd <project dir>
                     claude --resume <id>
                     (or codex resume <id>)
```

Each JSONL session is converted to markdown with YAML frontmatter (session ID, project, date, slug) and the full conversation text. `session2md.sh` also maintains a local SQLite FTS5 index for ranked search. If `sqlite3` is unavailable, `sg` falls back to `rg` search.

## Performance

Benchmarked on 610 sessions (496 Claude Code + 114 Codex), 6.2 MB total on an M1 Mac.

| Operation | Time | How |
|-----------|------|-----|
| **List all 610 sessions** | **0.16s** | Single `gawk` pass reads all frontmatters |
| **Content search (broad, 342 hits)** | **0.14s** | `rg` parallel grep + `gawk` format |
| **Content search (narrow, 5 hits)** | **0.06s** | `rg` + `gawk` on few files |
| **Incremental re-index (2 changed)** | **~1s** | `session2md.sh` skips unchanged files |
| **Full re-index (610 sessions)** | **~45s** | One-time `jq` conversion of all JSONL |

Live content search runs on every keystroke via fzf's `--disabled` + `change:reload`, using SQLite FTS5 ranking when available with `rg` fallback. Feels instant.

## Install

```bash
# 1. Dependencies
brew install jq fzf gawk ripgrep

# 2. Clone and symlink
git clone https://github.com/andresc-cw/agent-grep.git
cd agent-grep
ln -s "$(pwd)/sg" ~/.local/bin/sg

# 3. Initial index
./session2md.sh

# 4. (Optional) Auto-index every 5 minutes
cp com.agent-grep.session2md.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.agent-grep.session2md.plist
```

## Dependencies

| Tool | Purpose | Install |
|------|---------|---------|
| [fzf](https://github.com/junegunn/fzf) | Interactive picker with preview | `brew install fzf` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Fast parallel content search | `brew install ripgrep` |
| [gawk](https://www.gnu.org/software/gawk/) | Frontmatter parsing (needs `ENDFILE`) | `brew install gawk` |
| [jq](https://github.com/jqlang/jq) | JSONL to markdown conversion | `brew install jq` |
| [sqlite3](https://www.sqlite.org/) | Ranked full-text search (FTS5) | included on macOS |

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
| `.sg_idx.awk` | gawk program for metadata extraction into FTS |
| `com.agent-grep.session2md.plist` | launchd plist for background indexing |
