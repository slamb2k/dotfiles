#!/usr/bin/env bash
set -euo pipefail

pane_pid="${1:-}"
pane_command="${2:-}"
tmux_host_name="${3:-}"

short_name() {
  local value="$1"
  value="${value#*@}"
  value="${value%%:*}"
  printf '%s' "$value"
}

label_from_ssh_args() {
  local args="$1"
  read -r -a parts <<< "$args"

  local skip_next=0 arg
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

find_child_command() {
  local wanted="$1" queue=() pid child comm args label
  [[ -n "$pane_pid" ]] || return 1
  queue=("$pane_pid")

  while ((${#queue[@]})); do
    pid="${queue[0]}"
    queue=("${queue[@]:1}")
    comm="$(ps -p "$pid" -o comm= 2>/dev/null || true)"

    if [[ "${comm##*/}" == "$wanted" ]]; then
      args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
      printf '%s' "$args"
      return 0
    fi

    while read -r child; do
      [[ -n "$child" ]] && queue+=("$child")
    done < <(pgrep -P "$pid" 2>/dev/null || true)
  done

  return 1
}

if ssh_args="$(find_child_command ssh || true)" && [[ -n "$ssh_args" ]]; then
  ssh_name="$(label_from_ssh_args "$ssh_args" || true)"
  [[ -n "$ssh_name" ]] || ssh_name="remote"
  printf '󰣀 %s' "$ssh_name"
  exit 0
fi

friendly_tmux_ssh_name="$(tmux showenv -g TMUX_SSH_CONNECTION_NAME 2>/dev/null | sed 's/^TMUX_SSH_CONNECTION_NAME=//' || true)"
if [[ -n "$friendly_tmux_ssh_name" ]]; then
  printf '󰣀 %s' "$friendly_tmux_ssh_name"
  exit 0
fi

if tmux showenv -g SSH_CONNECTION >/dev/null 2>&1; then
  printf '󰣀 %s' "${tmux_host_name:-remote}"
  exit 0
fi

case "${pane_command,,}" in
  powershell.exe|powershell)
    printf ' PowerShell'
    exit 0
    ;;
  pwsh.exe|pwsh)
    printf ' pwsh'
    exit 0
    ;;
  cmd.exe|cmd)
    printf ' cmd'
    exit 0
    ;;
esac

if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
  printf ' %s' "$WSL_DISTRO_NAME"
  exit 0
fi

if grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null; then
  distro="$(. /etc/os-release 2>/dev/null && printf '%s' "${NAME:-WSL}" || printf WSL)"
  printf ' %s' "$distro"
  exit 0
fi

printf ' local'
