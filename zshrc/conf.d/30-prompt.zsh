# Prompt + shell integrations
eval "$(starship init zsh)"

# Keep the full two-line Starship prompt only for the active prompt.
# Before accepting a line, redraw the current prompt as a compact one-line
# prompt. The next prompt still uses the full Starship format.
function starship_transient_accept_line {
  local old_prompt="$PROMPT"
  local old_rprompt="$RPROMPT"
  local old_prompt2="$PROMPT2"

  PROMPT='$(starship module character)'
  RPROMPT=''
  PROMPT2=''
  zle reset-prompt

  PROMPT="$old_prompt"
  RPROMPT="$old_rprompt"
  PROMPT2="$old_prompt2"
  zle .accept-line
}

zle -N accept-line starship_transient_accept_line

eval "$(zoxide init zsh)"
eval "$(atuin init zsh)"
eval "$(direnv hook zsh)"
command -v mise &>/dev/null && eval "$(mise activate zsh)"
