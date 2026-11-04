# Loader. Real configuration lives in $ZDOTDIR/conf.d/*.zsh, sourced in
# lexical order:
#   00-env          exports + PATH
#   10-completions  completion system + tool completions
#   20-keybindings  bindkey calls
#   30-prompt       starship/atuin/zoxide/direnv/mise hooks
#   40-aliases      all aliases, grouped
#   50-functions    shell functions

ZDOTDIR="${ZDOTDIR:-$HOME/.config/zshrc}"
for _f in "$ZDOTDIR"/conf.d/*.zsh(N); do
  source "$_f"
done
unset _f

# >>> setec-astronomy >>>
# Keeper-backed env vars (github.com/slamb2k/setec-astronomy; its install.sh puts the script here).
# The list stays in this repo so every machine shares it.
KEEPER_SECRETS_LIST="$ZDOTDIR/keeper-secrets.list"
[[ -r "$HOME/.local/share/setec-astronomy/setec-astronomy.zsh" ]] && source "$HOME/.local/share/setec-astronomy/setec-astronomy.zsh"
# <<< setec-astronomy <<<

# Per-machine overrides — gitignored, optional.
[[ -r "$ZDOTDIR/.zshrc.local" ]] && source "$ZDOTDIR/.zshrc.local"

# Atuin is installed via linuxbrew — brew manages PATH, so no env file needed.
eval "$(atuin init zsh)"

# bun completions
[ -s "/home/slamb2k/.bun/_bun" ] && source "/home/slamb2k/.bun/_bun"
