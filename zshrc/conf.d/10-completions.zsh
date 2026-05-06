# Case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# bash completion bridge (for tools that ship bash completions only)
autoload -Uz bashcompinit && bashcompinit

# zsh completions with daily cache rebuild — dump goes to $XDG_CACHE_HOME, not
# the dotfiles repo.
ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
[[ -d $ZSH_CACHE_DIR ]] || mkdir -p "$ZSH_CACHE_DIR"
ZSH_COMPDUMP="$ZSH_CACHE_DIR/.zcompdump"
autoload -Uz compinit
if [[ -f $ZSH_COMPDUMP(#qNmh-20) ]]; then
  compinit -C -d "$ZSH_COMPDUMP"
else
  compinit -d "$ZSH_COMPDUMP"
fi

# Tool-specific completions (guarded — silent when tool absent)
command -v kubectl &>/dev/null && source <(kubectl completion zsh)
[[ -x /usr/local/bin/aws_completer ]] && complete -C /usr/local/bin/aws_completer aws

# zsh-autosuggestions (installed via Brewfile)
if [[ -n $HOMEBREW_PREFIX ]]; then
  _autosuggest="$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  [[ -r $_autosuggest ]] && source "$_autosuggest"
  unset _autosuggest
fi
