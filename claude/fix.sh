#!/usr/bin/env bash
# Claude package drift fixer. Called by ../setup.sh --check --fix.
set -euo pipefail

REPO=${DOTFILES_REPO:-$(cd "$(dirname "$0")/.." && pwd)}
CLAUDE_PKG="$REPO/claude"
TYPE=${1:?type required}
ID=${2:?id required}
STATE=${3:-}
ACTION=${4:-default}

say_ok()   { printf "    \033[32m✓️ %s\033[0m\n" "$*"; }
say_warn() { printf "    \033[33m⚠️ %s\033[0m\n" "$*"; }

stow_claude() {
  stow --target="$HOME" -d "$REPO" claude || return 1
  [[ -x "$CLAUDE_PKG/apply.sh" ]] && bash "$CLAUDE_PKG/apply.sh" >/dev/null
}

generate_skill_lock() {
  local dest="$CLAUDE_PKG/.skill-lock.json"
  mkdir -p "$CLAUDE_PKG" "$HOME/.agents"
  if [[ -f "$HOME/.agents/.skill-lock.json" ]]; then
    cp -L "$HOME/.agents/.skill-lock.json" "$dest"
    say_ok "exported skill lock from ~/.agents/.skill-lock.json"
  elif [[ -f "$HOME/dotfiles-old/claude/.skill-lock.json" ]]; then
    cp "$HOME/dotfiles-old/claude/.skill-lock.json" "$dest"
    say_ok "seeded skill lock from ~/dotfiles-old/claude/.skill-lock.json"
  else
    say_warn "no existing skills lock found; install third-party skills with npx skills, then rerun --check --fix"
    return 1
  fi
  ln -sfn "$dest" "$HOME/.agents/.skill-lock.json"
  say_ok "linked ~/.agents/.skill-lock.json -> claude/.skill-lock.json"
}

generate_plugin_lock() {
  local dest="$CLAUDE_PKG/plugins.lock.json"
  mkdir -p "$CLAUDE_PKG"
  python3 - "$dest" "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" <<'PY'
import json, pathlib, sys
out=pathlib.Path(sys.argv[1])
settings={}
installed={}
for path, target in [(sys.argv[2], 'settings'), (sys.argv[3], 'installed')]:
    try:
        data=json.load(open(path))
    except FileNotFoundError:
        data={}
    if target == 'settings': settings=data
    else: installed=data
plugins={}
enabled=settings.get('enabledPlugins') or {}
installed_plugins=installed.get('plugins') or {}
for name in sorted(set(enabled) | set(installed_plugins)):
    entries=installed_plugins.get(name) or []
    scopes=sorted({e.get('scope','user') for e in entries}) or ['user']
    versions=sorted({e.get('version') for e in entries if e.get('version') and e.get('version') != 'unknown'})
    plugins[name]={'enabled': bool(enabled.get(name, False)), 'scopes': scopes}
    if versions:
        plugins[name]['versions']=versions
lock={'version':1,'marketplaces': settings.get('extraKnownMarketplaces') or {},'plugins': plugins}
out.write_text(json.dumps(lock, indent=2, sort_keys=True)+'\n')
PY
  say_ok "exported plugin lock from live Claude settings/plugin state"
}

case "$TYPE" in
  symlink)
    case "$STATE" in
      real-file)
        mkdir -p "$(dirname "$CLAUDE_PKG/.claude/$ID")"
        mv "$HOME/.claude/$ID" "$CLAUDE_PKG/.claude/$ID" \
          && stow_claude \
          && say_ok "absorbed claude/$ID" \
          || say_warn "absorb claude/$ID failed"
        ;;
      missing)
        stow_claude && say_ok "restowed claude/$ID" || say_warn "restow failed"
        ;;
      symlink-elsewhere)
        rm -f "$HOME/.claude/$ID" && stow_claude && say_ok "fixed claude/$ID" || say_warn "fix failed"
        ;;
    esac
    ;;
  adopt)
    if [[ $ACTION == ignore ]]; then
      printf "%s\n" "$ID" >> "$REPO/.adopt-ignore"
      say_ok "added $ID to .adopt-ignore"
    else
      sub=${ID%/*}
      mkdir -p "$CLAUDE_PKG/.claude/$sub"
      mv "$HOME/.claude/$ID" "$CLAUDE_PKG/.claude/$ID" \
        && stow_claude \
        && say_ok "adopted $ID" \
        || say_warn "adopt $ID failed"
    fi
    ;;
  lock)
    case "$ID" in
      skills-lock)      generate_skill_lock ;;
      skills-lock-link) mkdir -p "$HOME/.agents" && ln -sfn "$CLAUDE_PKG/.skill-lock.json" "$HOME/.agents/.skill-lock.json" && say_ok "fixed ~/.agents/.skill-lock.json symlink" ;;
      plugins-lock)     generate_plugin_lock ;;
    esac
    ;;
  *)
    say_warn "unknown Claude drift type: $TYPE"
    exit 1
    ;;
esac
