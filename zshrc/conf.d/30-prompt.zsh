# Prompt + shell integrations
eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
eval "$(atuin init zsh)"
eval "$(direnv hook zsh)"
command -v mise &>/dev/null && eval "$(mise activate zsh)"
