# Title computed in the shell so it's correct on every box, including through
# ssh inside a local tmux where OSC 7 never reaches the outer terminal.
# tmux captures this OSC 0 as the pane title (#T) and forwards it (set-titles).
autoload -Uz add-zsh-hook

__title_is_remote() {
  [[ -n $SSH_CONNECTION ]] && return 0
  [[ -z $WSL_DISTRO_NAME && $OSTYPE != darwin* ]] && return 0
  return 1
}

__title_body() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -n $root ]]; then print -r -- "${root:t}"; else print -rP -- '%2~'; fi
}

__title_emit() {
  local body=$1
  if __title_is_remote; then
    printf '\e]0;%s: %s\a' "${HOST%%.*}" "$body"
  else
    printf '\e]0;%s\a' "$body"
  fi
}

__title_precmd()  { __title_emit "$(__title_body)"; }
__title_preexec() { __title_emit "${1%% *}"; }

add-zsh-hook precmd  __title_precmd
add-zsh-hook preexec __title_preexec
