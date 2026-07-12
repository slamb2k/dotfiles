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
  local script=$HOME/dotfiles/setup.sh
  local marker=$HOME/.cache/dotfiles-drift-checked
  [[ -x $script ]] || return
  mkdir -p "${marker%/*}"
  if [[ ! -f $marker ]] || [[ -n $(find "$marker" -mtime +0 2>/dev/null) ]]; then
    "$script" --check --quiet
    touch "$marker"
  fi
}
__dotfiles_drift_check
unset -f __dotfiles_drift_check

# Claude Code helpers
unalias ccq 2>/dev/null
ccq() { ~/.claude/scripts/ccq.sh "$@"; }

claude-update-plugins() {
  emulate -L zsh
  local failed=0

  echo "Updating marketplaces..."
  claude plugin marketplace update || failed=1

  echo "Updating plugins..."
  local -a plugins
  local plugin

  if command -v jq >/dev/null 2>&1; then
    plugins=("${(@f)$(claude plugin list --json | jq -r '.[].id')}")
  else
    plugins=("${(@f)$(claude plugin list | sed -n 's/^[[:space:]]*❯[[:space:]]*//p')}")
  fi

  for plugin in "${plugins[@]}"; do
    [[ -n "$plugin" ]] || continue
    echo "  - $plugin"
    claude plugin update "$plugin" || failed=1
  done

  if (( failed )); then
    echo "Finished with errors. Restart Claude Code to apply any successful updates."
    return 1
  fi

  echo "Done. Restart Claude Code to apply changes."
}
claude-update-plugin() { claude-update-plugins "$@"; }

claude-cloud() {
  ssh vm-alwayson-dev-claude -t "tmux new-session -A -s claude"
}

ccs() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: ccs <project> [project2 ...]" >&2
    echo "Available: $(ls ~/work/)" >&2
    return 1
  fi

  local dirs=()
  local project dir
  for project in "$@"; do
    dir="$HOME/work/$project"
    if [[ ! -d "$dir" ]]; then
      echo "Directory not found: $dir" >&2
      return 1
    fi
    dirs+=("$dir")
  done

  tmux new-window -n "claude-multi" -c "${dirs[1]}" "claude"
  for dir in "${dirs[@]:1}"; do
    tmux split-window -t "claude-multi" -c "$dir" "claude"
    tmux select-layout -t "claude-multi" tiled
  done
}

ccl() {
  echo "Claude Code sessions:"
  tmux list-panes -a -F '  #{window_name} | #{pane_current_command} | #{pane_current_path}' 2>/dev/null \
    | grep -i claude
  local count
  count=$(tmux list-panes -a -F '#{pane_current_command}' 2>/dev/null | grep -ci claude || true)
  echo "  ($count active)"
}

# Remote VS Code: open current Linux path from the workstation via SSH.
code() {
  local target="${1:-.}" abs
  abs="$(cd "$target" 2>/dev/null && pwd)" || { echo "no such dir: $target" >&2; return 1; }
  # WORKSTATION = SSH host alias on the VM pointing at your Win11 box's tailnet name
  # REMOTE_ALIAS must match a Host entry in the WORKSTATION's ~/.ssh/config
  local WORKSTATION="velrada-pc" REMOTE_ALIAS="vm-always"
  ssh "$WORKSTATION" "code --remote ssh-remote+${REMOTE_ALIAS} \"${abs}\""
}

# tmux: swallow stray paste bytes that arrive after a command finishes.
zle-line-init() {
  if [[ -n "$TMUX" ]]; then
    while read -t 0.05 -k 1 2>/dev/null; do :; done
  fi
}
zle -N zle-line-init

# azlogin/azlogin-debug retired 2026-07-08 — superseded by azrl (browser
# bridge, profile bookkeeping, git credential integration). Sign in with
# `azrl login <profile>` on the VM; it bridges the browser automatically.
azlogin() { print "azlogin retired — run \`azrl login <profile>\` instead (azrl bridges the browser)" >&2; return 1 }
azlogin-debug() { azlogin }
