# Cross-platform clipboard write (reads from stdin, writes to system clipboard)
_clipcopy() {
  if   command -v clip.exe &>/dev/null; then clip.exe                   # WSL → Windows
  elif command -v pbcopy   &>/dev/null; then pbcopy                     # macOS
  elif command -v wl-copy  &>/dev/null; then wl-copy                    # Wayland
  elif command -v xclip    &>/dev/null; then xclip -selection clipboard # X11
  else cat
  fi
}

# Navigation
cx()  { cd "$@" && l; }
fcd() { cd "$(find . -type d -not -path '*/.*' | fzf)" && l; }
f()   { find . -type f -not -path '*/.*' | fzf | _clipcopy; }
fv()  { nvim "$(find . -type f -not -path '*/.*' | fzf)"; }

# Ranger that cd's to its exit dir
ranger() {
  local IFS=$'\t\n'
  local tempfile="$(mktemp -t tmp.XXXXXX)"
  command ranger --cmd="map Q chain shell echo %d > \"$tempfile\"; quitall" "$@"
  if [[ -f "$tempfile" && "$(<"$tempfile")" != "$PWD" ]]; then
    cd -- "$(<"$tempfile")" || return
  fi
  command rm -f -- "$tempfile" 2>/dev/null
}
alias rr='ranger'

# Dotfiles drift check — runs once per day on shell startup. Silent when clean,
# prints a one-line summary when something's installed but not yet tracked.
__dotfiles_drift_check() {
  local script=$HOME/dotfiles/check-drift.sh
  local marker=$HOME/.cache/dotfiles-drift-checked
  [[ -x $script ]] || return
  mkdir -p "${marker%/*}"
  if [[ ! -f $marker ]] || [[ -n $(find "$marker" -mtime +0 2>/dev/null) ]]; then
    "$script" --quiet
    touch "$marker"
  fi
}
__dotfiles_drift_check
unset -f __dotfiles_drift_check
