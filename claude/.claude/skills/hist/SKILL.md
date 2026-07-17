---
name: hist
description: Search the user's Claude Code conversation history across all projects. Use when the user asks about past sessions or conversations ("when did I...", "which session did we...", "have I worked on X before", "search my history"), or types /hist <query>.
---

# hist — Claude Code history search

Search all transcripts under `~/.claude/projects/` with the `claude-hist` CLI
(SQLite FTS5 index, auto-refreshed on every search).

## Commands

```bash
claude-hist "search terms"              # ranked results grouped by session
claude-hist "terms" -p <project>        # project name contains <project>
claude-hist "terms" --since 2026-06 --until 2026-07
claude-hist "terms" --role user         # only what the user typed
claude-hist "terms" -n 20 -m 5          # more sessions / snippets
claude-hist "terms" --raw               # raw FTS5 syntax (OR, NEAR, *)
claude-hist show <session-id>           # full conversation (prefix id ok)
claude-hist reindex                     # full rebuild if results look stale
```

## How to answer history questions

1. Turn the user's question into 1–3 distinctive search terms (terms are
   ANDed; prefer rare words like an error string, tool name, or filename over
   common ones). Try `--raw "term1 OR term2"` if AND finds nothing.
2. Run `claude-hist` via Bash. Output is plain text; each result block is:
   title, `project · date · session-id`, then matched snippets.
3. Summarize the relevant sessions for the user — title, project, date, and
   what happened — and include the session id so they can run
   `claude-hist show <id>` themselves.
4. For "what did we decide/do" questions, follow up with
   `claude-hist show <id>` and read the relevant part rather than guessing
   from snippets. Pipe through grep/head for long sessions.

Searches only real conversation text (user prompts + assistant replies);
tool output, thinking, and hook noise are not indexed.
