#!/usr/bin/env bash
# Wraps `claude-statusline prompt`, splicing in segments claude-statusline
# has no module for:
#   - an open-follow-ups count from the current project's LOGBOOK.md (mad-
#     skills' /logbook ledger), inserted between $git_branch and $model
#   - the model Claude Code's native `advisor` tool is configured to use
#     (~/.claude/settings.json's "advisorModel"), inserted between $model
#     and $context (the slot $cost used to occupy)
#   - the 5-hour and 7-day rate-limit usage windows (statusLine JSON's
#     rate_limits.five_hour/seven_day.used_percentage), as compact text
#     (not bars — one progress bar, $context's, is enough), inserted right
#     before $context
# so the final order is: directory, git_branch, logbook, model, advisor,
# usage, context — $context stays last either way. Falls back to the plain
# claude-statusline line, untouched, if anything below fails — this must
# never break the status line render.
#
# Single-render design: renders ONCE (an earlier version did a left/right
# split render to control insertion position — 2x claude-statusline calls)
# and splices both segments in via literal-substring search for $model's and
# $context's ANSI color prefixes. Those prefixes are HARDCODED below rather
# than derived from config.toml on every call — deriving them costs extra
# subprocess calls for roughly what it saves by not double-rendering, a net
# wash once measured. If you change [model]'s or [context]'s style in
# config.toml, update MODEL_ANCHOR / CONTEXT_ANCHOR to match; if either ever
# drifts out of sync the fallback below just appends that segment at the end
# instead of crashing.
#
# Evaluated switching to ccstatusline (native custom-command widget, no
# splicing needed at all) but its Node/Bun startup cost measured ~220ms/
# render — ~65x slower than this Go binary — so that path was abandoned.
set -uo pipefail

# fg:#ffffff bg:#312e81 bold — must match config.toml's [model] style.
MODEL_ANCHOR=$'\033[38;2;255;255;255;48;2;49;46;129;1m'
# fg:#ffffff bg:#9a3412 — must match config.toml's [context] style.
CONTEXT_ANCHOR=$'\033[38;2;255;255;255;48;2;154;52;18m'

splice() {
  # $1=anchor $2=segment; reads full line on stdin, inserts segment right
  # before anchor's first occurrence, or appends it if the anchor isn't found.
  LC_ALL=C awk -v anchor="$1" -v seg="$2" '
    { idx = index($0, anchor);
      if (idx > 0) print substr($0,1,idx-1) seg substr($0,idx);
      else print $0 seg;
    }'
}

payload="$(cat)"
full="$(printf '%s' "$payload" | claude-statusline prompt)"

dir="$(printf '%s' "$payload" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)"
repo_root=""
[ -n "$dir" ] && repo_root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
logbook="$repo_root/LOGBOOK.md"

advisor_model="$(jq -r '.advisorModel // empty' "$HOME/.claude/settings.json" 2>/dev/null)"
advisor_label="${advisor_model^}"
[ -z "$advisor_label" ] && advisor_label="unset"
advisor_segment="$(printf '\033[38;2;255;255;255;48;2;131;24;67m ◇ %s \033[0m' "$advisor_label")"

five_hour="$(printf '%s' "$payload" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)"
seven_day="$(printf '%s' "$payload" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)"
usage_segment=""
if [ -n "$five_hour" ] || [ -n "$seven_day" ]; then
  five_hour_i="$(printf '%.0f' "${five_hour:-0}" 2>/dev/null || echo 0)"
  seven_day_i="$(printf '%.0f' "${seven_day:-0}" 2>/dev/null || echo 0)"
  usage_segment="$(printf '\033[38;2;255;255;255;48;2;22;78;99m 5h %s%% · 7d %s%% \033[0m' "$five_hour_i" "$seven_day_i")"
fi

if [ -n "$repo_root" ] && [ -f "$logbook" ]; then
  count="$(grep -c '^- \[ \]' "$logbook" 2>/dev/null || true)"
  count="${count:-0}"
  # Reuse the amber shade freed up by removing $cost so this reads as a
  # themed segment rather than a bolted-on extra.
  logbook_segment="$(printf '\033[38;2;255;255;255;48;2;120;53;15m ⚐ %s \033[0m' "$count")"
  full="$(splice "$MODEL_ANCHOR" "$logbook_segment" <<<"$full")"
fi

full="$(splice "$CONTEXT_ANCHOR" "$advisor_segment" <<<"$full")"
if [ -n "$usage_segment" ]; then
  full="$(splice "$CONTEXT_ANCHOR" "$usage_segment" <<<"$full")"
fi
printf '%s\n' "$full"
