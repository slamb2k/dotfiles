#!/usr/bin/env bash
set -euo pipefail

status=""
percent=""

# Linux / WSL / most laptops
for bat in /sys/class/power_supply/BAT* /sys/class/power_supply/battery*; do
  [[ -d "$bat" ]] || continue
  [[ -r "$bat/status" ]] && status="$(tr '[:upper:]' '[:lower:]' < "$bat/status")"
  [[ -r "$bat/capacity" ]] && percent="$(<"$bat/capacity")%"
  break
done

# acpi fallback
if [[ -z "$status" ]] && command -v acpi >/dev/null 2>&1; then
  line="$(acpi -b 2>/dev/null | head -n1 || true)"
  status="$(awk -F'[:, ]+' '{print tolower($3)}' <<<"$line")"
  percent="$(grep -oE '[0-9]+%' <<<"$line" | head -n1 || true)"
fi

# macOS fallback
if [[ -z "$status" ]] && command -v pmset >/dev/null 2>&1; then
  line="$(pmset -g batt 2>/dev/null | awk -F '; *' 'NR==2 {print}' || true)"
  status="$(awk -F '; *' '{print tolower($2)}' <<<"$line")"
  percent="$(grep -oE '[0-9]+%' <<<"$line" | head -n1 || true)"
fi

[[ "$status" == "discharging" ]] || exit 0
[[ -n "$percent" ]] || exit 0

# Catppuccin-style rounded tile: lavender icon segment + surface text segment.
printf '#[fg=#b4befe]#[fg=#11111b,bg=#b4befe]🔋 #[fg=#cdd6f4,bg=#313244] %s#[fg=#313244] ' "$percent"
