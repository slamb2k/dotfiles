# zsh reads this instead of ~/.zshenv when ZDOTDIR is already set, i.e. in every child zsh
# (scripts, Claude Code, MCP servers), so the PATH setup has to be repeated here.
[[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
[[ -r "$ZDOTDIR/env/path.zsh" ]] && . "$ZDOTDIR/env/path.zsh"
