#!/usr/bin/env bash
# Claude package drift detector.
#
# Default output is TSV records consumed by ../setup.sh:
#   symlink<TAB>rel<TAB>state<TAB>message
#   adopt<TAB>sub/name<TAB>candidate<TAB>message
#   lock<TAB>id<TAB>state<TAB>message
set -euo pipefail

REPO=${DOTFILES_REPO:-$(cd "$(dirname "$0")/.." && pwd)}
CLAUDE_PKG="$REPO/claude"

emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }

is_ignored() {
  local path=$1 pattern ignore_file="$REPO/.adopt-ignore"
  [[ -f $ignore_file ]] || return 1
  while IFS= read -r pattern; do
    [[ -z $pattern || $pattern == \#* ]] && continue
    # shellcheck disable=SC2053
    [[ $path == $pattern ]] && return 0
  done < "$ignore_file"
  return 1
}

check_symlinks() {
  [[ -d $CLAUDE_PKG/.claude ]] || return 0
  local f rel target
  while IFS= read -r -d '' f; do
    rel=${f#$CLAUDE_PKG/.claude/}
    target=$HOME/.claude/$rel
    if [[ -L $target ]]; then
      [[ "$(readlink -f "$target")" == "$(readlink -f "$f")" ]] && continue
      emit symlink "$rel" symlink-elsewhere "$rel (symlink points elsewhere)"
    elif [[ -e $target ]]; then
      emit symlink "$rel" real-file "$rel (real file — atomic write replaced symlink; mv into package + restow)"
    else
      emit symlink "$rel" missing "$rel (missing — run \`cd ~/dotfiles && stow --target=\$HOME -d ~/dotfiles claude\`)"
    fi
  done < <(find "$CLAUDE_PKG/.claude" -type f -print0)
}

check_adoption() {
  local sub live_dir pkg_dir entry name
  for sub in skills agents hooks; do
    live_dir="$HOME/.claude/$sub"
    pkg_dir="$CLAUDE_PKG/.claude/$sub"
    [[ -d $live_dir ]] || continue
    for entry in "$live_dir"/*; do
      [[ -e $entry ]] || continue
      name=${entry##*/}
      if [[ -L $entry && "$(readlink -f "$entry")" == "$pkg_dir/$name" ]]; then
        continue
      fi
      # npx skills canonical symlinks are managed by .skill-lock.json, not adopted.
      if [[ $sub == skills && -L $entry && "$(readlink -f "$entry")" == "$HOME/.agents/skills/$name" ]]; then
        continue
      fi
      [[ -e "$pkg_dir/$name" ]] && continue
      is_ignored "$sub/$name" && continue
      emit adopt "$sub/$name" candidate "$sub/$name"
    done
  done
}

check_locks() {
  local skill_lock="$CLAUDE_PKG/.skill-lock.json"
  local live_skill_lock="$HOME/.agents/.skill-lock.json"
  if [[ ! -f $skill_lock ]]; then
    emit lock skills-lock missing "skills lock missing at claude/.skill-lock.json"
  fi
  if [[ -L $live_skill_lock ]]; then
    if [[ ! -e $live_skill_lock ]]; then
      emit lock skills-lock-link broken "~/.agents/.skill-lock.json symlink is broken"
    elif [[ -f $skill_lock && "$(readlink -f "$live_skill_lock")" != "$(readlink -f "$skill_lock")" ]]; then
      emit lock skills-lock-link drift "~/.agents/.skill-lock.json points outside dotfiles"
    fi
  elif [[ -e $live_skill_lock ]]; then
    emit lock skills-lock-link drift "~/.agents/.skill-lock.json is a real file, not dotfiles symlink"
  elif [[ -f $skill_lock ]]; then
    emit lock skills-lock-link missing "~/.agents/.skill-lock.json missing"
  fi

  local plugin_lock="$CLAUDE_PKG/plugins.lock.json"
  if [[ ! -f $plugin_lock ]]; then
    emit lock plugins-lock missing "plugins lock missing at claude/plugins.lock.json"
  elif [[ -f $HOME/.claude/settings.json ]]; then
    local plugin_diff
    plugin_diff=$(python3 - "$plugin_lock" "$HOME/.claude/settings.json" <<'PY' 2>/dev/null || true
import json, sys
lock=json.load(open(sys.argv[1]))
settings=json.load(open(sys.argv[2]))
locked=set(k for k,v in (lock.get('plugins') or {}).items() if (v or {}).get('enabled'))
live=set(k for k,v in (settings.get('enabledPlugins') or {}).items() if v)
if sorted(live-locked) or sorted(locked-live):
    print('live enabledPlugins differ from claude/plugins.lock.json')
PY
)
    [[ -n $plugin_diff ]] && emit lock plugins-lock drift "$plugin_diff"
  fi
}

check_symlinks
check_adoption
check_locks
