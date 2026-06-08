#!/usr/bin/env bash
set -euo pipefail

# Show a styled SSH badge for the active tmux pane.
# If the pane is running `ssh <connection>`, the connection name is extracted
# from the ssh command. If tmux itself is hosted over SSH, fall back to the
# remote hostname. Override with TMUX_SSH_CONNECTION_NAME for a friendly label.

pane_pid="${1:-}"

short_name() {
  local value="$1"
  value="${value#*@}"      # user@host -> host
  value="${value%%:*}"     # host:path -> host
  printf '%s' "$value"
}

label_from_ssh_args() {
  local args="$1"
  # Best-effort parsing of common ssh invocations. This handles aliases,
  # user@host, and most short/long options before the destination.
  read -r -a parts <<< "$args"

  local skip_next=0
  local arg
  for arg in "${parts[@]:1}"; do
    if (( skip_next )); then
      skip_next=0
      continue
    fi

    case "$arg" in
      -b|-c|-D|-E|-e|-F|-I|-i|-J|-L|-l|-m|-O|-o|-p|-Q|-R|-S|-W|-w)
        skip_next=1
        continue
        ;;
      --)
        continue
        ;;
      -*)
        continue
        ;;
      *)
        short_name "$arg"
        return 0
        ;;
    esac
  done

  return 1
}

find_ssh_label() {
  local queue=() pid child comm args label
  [[ -n "$pane_pid" ]] || return 1
  queue=("$pane_pid")

  while ((${#queue[@]})); do
    pid="${queue[0]}"
    queue=("${queue[@]:1}")

    comm="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    if [[ "${comm##*/}" == "ssh" ]]; then
      args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
      label="$(label_from_ssh_args "$args" || true)"
      [[ -n "$label" ]] && printf '%s' "$label" && return 0
    fi

    while read -r child; do
      [[ -n "$child" ]] && queue+=("$child")
    done < <(pgrep -P "$pid" 2>/dev/null || true)
  done

  return 1
}

name="${TMUX_SSH_CONNECTION_NAME:-}"
if [[ -z "$name" ]]; then
  name="$(find_ssh_label || true)"
fi

# Fallback for tmux sessions that are themselves running on a remote host.
if [[ -z "$name" && -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}" ]]; then
  name="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf remote)"
fi

[[ -n "$name" ]] || exit 0
printf '#[fg=#05070a,bg=#89b4fa,bold] 󰣀 SSH %s #[default]' "$name"
