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

[[ -d "$HOME/.cargo/bin" ]]               && path=("$HOME/.cargo/bin" $path)
[[ -d "$HOME/.local/share/mise/shims" ]]  && path=("$HOME/.local/share/mise/shims" $path)
[[ -d "$HOME/.local/bin" ]]               && path=("$HOME/.local/bin" $path)
typeset -U path PATH

# Tool-specific exports
export KUBECONFIG="$HOME/.kube/config"
export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow'
