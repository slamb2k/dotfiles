# claude-hist — Claude Code history searcher

2026-07-17 · approved design (formal plan skipped by request)

## What

Full-text search over all Claude Code transcripts (`~/.claude/projects/**/*.jsonl`,
~667MB / ~1,100 sessions) for both the user (CLI) and Claude (skill).

## Components

- `claude/.local/bin/claude-hist` — single Python 3 script, stdlib only
  (sqlite3 + FTS5). Stows to `~/.local/bin` (on PATH).
- `claude/.claude/skills/hist/SKILL.md` — `/hist` skill telling Claude how to
  drive the CLI and summarize results.
- Index at `~/.claude/history.db` (not in the repo; rebuildable at any time).

## Behavior

- **Index**: `sessions` (id, project, title from `ai-title`/`summary` records,
  timestamps) + `messages` (user string content and assistant `text` blocks
  only) + FTS5 external-content table kept in sync by triggers.
  Skips sidechains, `isMeta`, tool_result/thinking blocks, `<system-reminder>`
  and local-command noise.
- **Incremental**: every search stats all jsonl files against stored
  mtime/size; only new/changed files re-parse; deleted files are pruned.
- **CLI**: `claude-hist "query"` (bm25-ranked, grouped by session, highlighted
  snippets), filters `-p/--role/--since/--until`, `--raw` for FTS5 syntax,
  `show <id>` for a full readable transcript, `reindex` for a full rebuild.

## Skipped (add if needed)

Semantic/embedding search, interactive TUI, file watching, cross-session
dedup of resumed/forked sessions, multi-machine sync.
