#!/usr/bin/env bash
dir="${1:-}"
[ -n "$dir" ] && [ -d "$dir" ] || exit 0
branch=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null) \
  || branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null) \
  || exit 0
[ -n "$branch" ] || exit 0

staged=0 modified=0 untracked=0
while IFS= read -r line; do
  x="${line:0:1}" y="${line:1:1}"
  if [ "$x" = "?" ]; then
    untracked=$((untracked + 1))
    continue
  fi
  [ "$x" != " " ] && staged=$((staged + 1))
  [ "$y" != " " ] && modified=$((modified + 1))
done < <(git -C "$dir" status --porcelain --no-renames 2>/dev/null)

changes=""
[ "$staged" -gt 0 ] && changes+=" +$staged"
[ "$modified" -gt 0 ] && changes+=" ~$modified"
[ "$untracked" -gt 0 ] && changes+=" ?$untracked"

printf '#[fg=#89dceb]\xee\x82\xa0 %s#[fg=#f9e2af]%s  ' "$branch" "$changes"
