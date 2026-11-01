# Shell options
setopt prompt_subst

# Locale + editor
export LANG=C.UTF-8
export EDITOR=nvim

# XDG dirs (be explicit so other tools agree)
export XDG_CONFIG_HOME="$HOME/.config"
export KSM_INI_DIR="$HOME/.config/ksm"

# ---- PATH: shared with non-interactive shells via ~/.zshenv -----------------
# Sourced again here so it still wins over anything system login files add.
source "${ZDOTDIR:-$HOME/.config/zshrc}/env/path.zsh"

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
