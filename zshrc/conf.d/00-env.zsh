# Shell options
setopt prompt_subst

# Locale + editor
export LANG=C.UTF-8
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

# Go (provided by Homebrew; do not force GOROOT to old /usr/local/go)
export GOPATH="$HOME/go"
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

# Browser (xdg-open default; overridden to wslview on WSL below)
export BROWSER=xdg-open

# Node Version Manager
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]]          && \. "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && \. "$NVM_DIR/bash_completion"

# WSL-specific integration (Windows paths, wslview browser)
if [[ -n "$WSL_DISTRO_NAME" ]]; then
  export PATH="$PATH:/mnt/c/Windows/system32:/mnt/c/Users/slamb2k/AppData/Local/Programs/Microsoft VS Code/bin"
  export USERPROFILE="/mnt/c/Users/SimonLamb"
  export BROWSER=wslview
fi

# GitHub Copilot CLI
export COPILOT_ALLOW_ALL=true
export GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=1
export GITHUB_COPILOT_PROMPT_MODE_WORKSPACE_MCP=1

# Claude Code
export CLAUDE_CODE_NO_FLICKER=1
