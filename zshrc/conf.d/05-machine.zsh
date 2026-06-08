# Machine detection helpers
# Sourced early so later conf.d/*.zsh can branch on local vs vm safely.
__is_vm()  { [[ -n "$SSH_CONNECTION" ]] }
__is_wsl() { [[ -n "$WSL_DISTRO_NAME" ]] }
