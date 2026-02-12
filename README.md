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
When you type a query, each row shows `[score:NNN/100]` (relative relevance for the current query; higher is better).

## Architecture

```
~/.claude/projects/**/*.jsonl ─┐
                               ├── session2md.sh (jq) ──► ~/.cache/agent-grep/sessions/*.md
~/.codex/sessions/**/*.jsonl ──┘                         │
                                                         ├── .sg_idx.awk + sqlite3
                                                         │         └── ~/.cache/agent-grep/sessions.sqlite (FTS5)
                                                         │
                       launchd (optional, every 5 min) ─┘

sg [query] [--repo <repo>] [--sort-date]
   │
   ├── helper script
   │     ├── SQLite FTS5 ranked path lookup (bm25)
   │     ├── fallback: rg -l path lookup (if sqlite3/db unavailable)
   │     ├── gawk (.sg_fmt.awk) frontmatter formatting
   │     └── repo filter + date-sort toggle state
   │
   └── fzf picker (live reload + preview)
           └── Enter: cd <project> && resume command from frontmatter
```

Each JSONL session is converted to markdown with YAML frontmatter (session ID, project, date, slug, resume command) and conversation text. `session2md.sh` also maintains a local SQLite FTS5 index for ranked search, and `sg` uses `rg` fallback when `sqlite3` is unavailable.

Current indexing behavior: any detected transcript change triggers an FTS rebuild over all indexed markdown files.

## Performance

Benchmarked on February 12, 2026 on an M1 Mac with:
- 646 indexed markdown sessions (`~/.cache/agent-grep/sessions`, 8.0 MB)
- 15 MB SQLite FTS database (`~/.cache/agent-grep/sessions.sqlite`)

List/search timings are mean wall-clock over 40 runs; indexing timings are single-run end-to-end measurements.

| Operation | Time | How |
|-----------|------|-----|
| **List all indexed sessions** | **0.11s** | `gawk` reads frontmatter from all markdown files |
| **FTS search (broad, `billing`, 354 hits)** | **0.10s** | SQLite FTS5 ranked lookup + `gawk` formatting |
| **FTS search (narrow, `launchctl`, 2 hits)** | **0.03s** | SQLite FTS5 ranked lookup + `gawk` formatting |
| **Fallback search (broad, `billing`)** | **0.13s** | `rg -l` path lookup + `gawk` formatting |
| **Incremental re-index (2 changed)** | **33.5s** | Re-convert changed JSONL + full FTS rebuild |
| **Full re-index (`--full`)** | **78.4s** | Re-convert all source sessions + full FTS rebuild |

Live content search in `fzf` uses `change:reload` with SQLite FTS5 ranking when available, with `rg` fallback.

## Install

```bash
# 1. Dependencies (macOS)
brew install jq fzf gawk ripgrep
# sqlite3 is preinstalled on macOS; verify:
sqlite3 --version

# Ubuntu/Debian
# sudo apt-get install -y jq fzf gawk ripgrep sqlite3

# 2. Clone and symlink
git clone https://github.com/andresc-cw/agent-grep.git
cd agent-grep
mkdir -p ~/.local/bin
ln -sfn "$(pwd)/sg" ~/.local/bin/sg
# ensure ~/.local/bin is on PATH in your shell config

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
