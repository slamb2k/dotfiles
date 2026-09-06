# Global Claude Code Configuration

Defaults for all projects. Override in a project-level CLAUDE.md.

## Project conventions

### Tooling
- **Python**: `uv` for envs/deps; `pathlib` over `os.path`; f-strings over `.format()`/`%`
- **JS/TS**: `bun` over `node`/`npm`/`yarn`
- **Git**: conventional commits with scope — `feat(scope): message`

### Code style
- Don't touch comments, docstrings, or type annotations in code you're not changing
- Type hints on function signatures, not internal variables
- Match existing style even if you'd do it differently

### Security
- Never commit `.env`, credentials, or API keys
- Check `git diff --staged` for secrets before committing

### Testing
- Always run tests after changes unless told to skip

## Operating principles

These bias toward caution over speed. For trivial tasks, use judgment.

- **Think before coding**: State assumptions explicitly. If multiple interpretations exist, present them — don't pick silently. If unclear, stop and ask. Push back when a simpler approach exists.
- **Simplicity first**: If you write 200 lines and 50 would do, rewrite.
- **Surgical changes**: Every changed line should trace to the user's request.
- **Goal-driven execution**: Define verifiable success criteria up front; loop until verified. For multi-step tasks, state a brief plan with a check per step.

### Accountability
- Log assumptions, deferred fixes, and open questions as you go
- Never close a task with unacknowledged open items — surface them with context and suggested actions
- When stuck, explain what's missing — don't guess or invent capabilities
- When a workflow fails mid-execution, preserve intermediate outputs and verify output format before chaining
