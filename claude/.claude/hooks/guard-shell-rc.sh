#!/usr/bin/env bash
# PreToolUse guard. This machine uses a modular ZDOTDIR setup, so ~/.zshrc and
# ~/.bashrc are NOT the real shell config and editing them has no effect.
# When an agent tries to WRITE one, deny the call and hand back the context it
# needs to edit the right file instead. Reads, and the real ~/dotfiles/zshrc
# files, are left alone.
set -euo pipefail

input="$(cat)"
tool="$(jq -r '.tool_name // empty' <<<"$input")"

case "$tool" in
  Edit|Write|MultiEdit) target="$(jq -r '.tool_input.file_path // empty' <<<"$input")" ;;
  Bash)                 target="$(jq -r '.tool_input.command // empty'  <<<"$input")" ;;
  *) exit 0 ;;
esac

# Expand a leading ~/ for matching.
norm="${target//\~\//$HOME/}"

# The real, modular config — never intervene on these.
if printf '%s' "$norm" | grep -qE 'dotfiles/zshrc|/\.config/zshrc|\.zshrc\.local|\.zshrc\.d/'; then
  exit 0
fi

# Does it touch a home-level rc file at all?
printf '%s' "$norm" | grep -qE '/\.(zshrc|bashrc)([^A-Za-z0-9_.]|$)' || exit 0

# For Bash, only intervene on writes — reading these files is fine. A write is
# a redirection whose TARGET is the rc file (so `2>&1` etc. don't count), or a
# tee / sed -i operating on it.
if [[ "$tool" == "Bash" ]]; then
  is_write=0
  # > rc   >> rc   > "$HOME/.zshrc"   (target chars stop at space, &, |, ;, <, >)
  if printf '%s' "$norm" | grep -qE ">>?[[:space:]]*['\"]?[^[:space:]|&;<>]*\.(zshrc|bashrc)"; then is_write=1; fi
  if printf '%s' "$norm" | grep -qE '(^|[[:space:]|;&])tee([[:space:]]|$)'; then is_write=1; fi
  if printf '%s' "$norm" | grep -qE '(^|[[:space:]|;&])sed[[:space:]][^|;&]*-i'; then is_write=1; fi
  [[ "$is_write" -eq 1 ]] || exit 0
fi

reason="$(cat <<'MSG'
STOP — this machine uses a modular ZDOTDIR setup. ~/.zshrc and ~/.bashrc are NOT
read by zsh; editing/creating them has no effect.

  • ~/.zshenv sets ZDOTDIR="$HOME/.config/zshrc"  (symlink -> ~/dotfiles/zshrc)
  • Loader ~/dotfiles/zshrc/.zshrc sources ~/dotfiles/zshrc/conf.d/*.zsh in
    lexical order:  00-env  10-completions  20-keybindings  30-prompt
                    40-aliases  50-functions
  • Tool init/hooks (starship, zoxide, atuin, direnv, mise) live in
    conf.d/30-prompt.zsh
  • Machine-specific, gitignored overrides: ~/dotfiles/zshrc/.zshrc.local

To add shell config: edit/create the appropriate ~/dotfiles/zshrc/conf.d/NN-*.zsh
(or .zshrc.local for machine-only bits) — NOT ~/.zshrc / ~/.bashrc.
FIRST grep ~/dotfiles/zshrc/conf.d to check whether the hook/alias/export already
exists; many tools are already wired up there.
MSG
)"

jq -n --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
