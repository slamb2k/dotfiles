# Report cwd to the terminal so new tabs/panes open in the same dir.
#   OSC 7   -> Warp, WezTerm, Ghostty, VS Code (Linux path)
#   OSC 9;9 -> Windows Terminal (Windows path via wslpath; WSL only)
autoload -Uz add-zsh-hook

__emit_cwd_osc() {
  # OSC 7: file://<host><path>, minimal percent-encoding for spaces
  printf '\e]7;file://%s%s\e\\' "${HOST:-$HOSTNAME}" "${PWD// /%20}"

  # OSC 9;9 for Windows Terminal sessions only
  if [[ -n $WT_SESSION ]] && (( $+commands[wslpath] )); then
    printf '\e]9;9;%s\e\\' "$(wslpath -w "$PWD")"
  fi
}
add-zsh-hook precmd __emit_cwd_osc
