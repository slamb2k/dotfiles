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

# Per-machine overrides — gitignored, optional.
[[ -r "$ZDOTDIR/.zshrc.local" ]] && source "$ZDOTDIR/.zshrc.local"
