#!/usr/bin/env bash
# Per-machine installer for the claude package's non-symlinkable bits.
#
# The hook SCRIPTS are stowed into ~/.claude/hooks/ as symlinks (see setup.sh /
# `stow --target=$HOME -d ~/dotfiles claude`). But ~/.claude/settings.json is a
# per-machine real file that Claude rewrites atomically, so we don't symlink it —
# instead this script idempotently merges the hook REGISTRATIONS into it.
#
# Safe to re-run: each registration is added only if its command isn't already
# present. Run once per machine after stowing the claude package.
set -euo pipefail

command -v jq >/dev/null || { echo "claude/install.sh: jq is required" >&2; exit 1; }

SETTINGS="$HOME/.claude/settings.json"
HOOK="$HOME/.claude/hooks/guard-shell-rc.sh"

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

register_pretooluse "Edit|Write|MultiEdit|Bash" "$HOOK" 10

echo "claude/install.sh: done. Open /hooks once (or restart) if a hook isn't picked up live."
