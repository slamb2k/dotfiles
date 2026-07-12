#!/usr/bin/env bash
# Apply/reconcile the Claude Code dotfiles package after stowing.
#
# This script owns Claude-specific mutable state that should not be represented
# as direct stow symlinks, especially ~/.claude/settings.json.
set -euo pipefail

command -v jq >/dev/null || { echo "claude/apply.sh: jq is required" >&2; exit 1; }

SETTINGS="$HOME/.claude/settings.json"
HOOK="$HOME/.claude/hooks/guard-shell-rc.sh"
DOTFILES_CLAUDE_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_LOCK="$DOTFILES_CLAUDE_DIR/.skill-lock.json"
PLUGIN_LOCK="$DOTFILES_CLAUDE_DIR/plugins.lock.json"

[[ -f "$SETTINGS" ]] || { mkdir -p "$(dirname "$SETTINGS")"; echo '{}' > "$SETTINGS"; }

register_pretooluse() {
  # $1 = matcher, $2 = absolute command path, $3 = timeout (seconds)
  local matcher="$1" cmd="$2" timeout="$3" tmp
  if jq -e --arg c "$cmd" '.hooks.PreToolUse[]?.hooks[]? | select(.command == $c)' \
       "$SETTINGS" >/dev/null 2>&1; then
    echo "• already registered: $cmd"
    return 0
  fi
  tmp="$(mktemp)"
  jq --arg m "$matcher" --arg c "$cmd" --argjson t "$timeout" \
    '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{
        matcher: $m,
        hooks: [{ type: "command", command: $c, timeout: $t }]
     }])' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "✓ registered: $cmd"
}

link_skill_lock() {
  [[ -f "$SKILL_LOCK" ]] || return 0
  mkdir -p "$HOME/.agents" "$HOME/.claude/skills"
  ln -sfn "$SKILL_LOCK" "$HOME/.agents/.skill-lock.json"
  echo "✓ linked: ~/.agents/.skill-lock.json"
}

link_npx_skill_shims() {
  # npx skills keeps canonical third-party skills in ~/.agents/skills and Claude
  # reads ~/.claude/skills. Ensure the Claude-facing shims exist without
  # overwriting real custom Claude skills.
  [[ -d "$HOME/.agents/skills" ]] || return 0
  mkdir -p "$HOME/.claude/skills"
  local skill_dir skill_name target
  for skill_dir in "$HOME/.agents/skills/"*/; do
    [[ -d "$skill_dir" ]] || continue
    skill_name=$(basename "$skill_dir")
    target="$HOME/.claude/skills/$skill_name"
    if [[ ! -e "$target" ]]; then
      ln -sfn "../../.agents/skills/$skill_name" "$target"
      echo "✓ linked skill shim: $skill_name"
    fi
  done
}

register_pretooluse "Edit|Write|MultiEdit|Bash" "$HOOK" 10
link_skill_lock
link_npx_skill_shims

if [[ -f "$PLUGIN_LOCK" ]]; then
  echo "• plugin lock present: $PLUGIN_LOCK (update via ./setup.sh --check --fix when drift is reported)"
fi

echo "claude/apply.sh: done. Open /hooks once (or restart) if a hook isn't picked up live."
