# azrl env applies a profile to the CURRENT shell — but a child process can't
# set its parent's environment, so this function shadows the binary and evals
# the `env` subcommand's exports in place (rbenv/direnv pattern). Everything
# else passes straight through to the real binary.
azrl() {
  if [[ "$1" == "env" ]]; then
    eval "$(command azrl env "${@:2}")"
  else
    command azrl "$@"
  fi
}

# Short prompt chip: "azure:simon.lamb@velrada.com" → "velrada.com".
# Starship's env_var module can't transform values, so precmd derives one.
_azrl_chip() {
  if [[ -n "$AZRL_PROFILE" ]]; then
    local n="${AZRL_PROFILE#*:}"    # drop the provider prefix
    export AZRL_CHIP="${n#*@}"      # email-style names show just the domain
  else
    unset AZRL_CHIP
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _azrl_chip
