# Shell options
setopt prompt_subst

# Locale + editor
export LANG=en_US.UTF-8
export EDITOR=nvim

# XDG dirs (be explicit so other tools agree)
export XDG_CONFIG_HOME="$HOME/.config"

# ---- PATH (rightmost = highest priority via path=( … $path )) --------------
# Homebrew (Linux WSL or macOS — whichever is present)
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Language/runtime/tool directories
[[ -d "$HOME/.cargo/bin" ]]               && path=("$HOME/.cargo/bin" $path)
[[ -d "$HOME/.local/share/mise/shims" ]]  && path=("$HOME/.local/share/mise/shims" $path)
[[ -d "$HOME/.local/bin" ]]               && path=("$HOME/.local/bin" $path)
[[ -d "$HOME/.bun/bin" ]]                 && path=("$HOME/.bun/bin" $path) && export BUN_INSTALL="$HOME/.bun"
[[ -d "$HOME/bin" ]]                      && path=("$HOME/bin" $path)

# .NET / Power Platform CLI
export DOTNET_ROOT="$HOME/.dotnet"
[[ -d $DOTNET_ROOT ]]                      && path=("$DOTNET_ROOT" $path)
[[ -d "$HOME/.local/pac/tools" ]]         && path=("$HOME/.local/pac/tools" $path)

# opencode
[[ -d "$HOME/.opencode/bin" ]]            && path=("$HOME/.opencode/bin" $path)

# Go
export GOROOT=/usr/local/go
export GOPATH="$HOME/go"
[[ -d "$GOROOT/bin" ]]                    && path=($path "$GOROOT/bin")
[[ -d "$GOPATH/bin" ]]                    && path=($path "$GOPATH/bin")

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
[[ -d $PNPM_HOME ]]                       && path=("$PNPM_HOME" $path)

typeset -U path PATH

# Tool-specific exports
export KUBECONFIG="$HOME/.kube/config"
export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow'
export CLOUDSDK_PYTHON=/usr/bin/python3

# Google Cloud SDK
[[ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]]       && source "$HOME/google-cloud-sdk/path.zsh.inc"
[[ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]] && source "$HOME/google-cloud-sdk/completion.zsh.inc"

# Browser
export BROWSER=xdg-open

# Claude Code
export CLAUDE_CODE_NO_FLICKER=1
export ANTHROPIC_DEFAULT_SONNET_MODEL='claude-sonnet-4-6[1m]'
export ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-4-6[1m]'
