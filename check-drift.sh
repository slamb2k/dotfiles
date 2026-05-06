#!/usr/bin/env bash
# check-drift.sh — detect untracked dev tools and configs.
#
# Usage:
#   ./check-drift.sh              # full report
#   ./check-drift.sh --quiet      # one-line summary only when drift exists
#                                 # (silent when clean — for shell startup)
#
# Exit code: 0 if clean, 1 if drift detected.

set -euo pipefail

QUIET=
[[ ${1:-} == --quiet || ${1:-} == -q ]] && QUIET=1

REPO=$(cd "$(dirname "$0")" && pwd)

# Items that .stowrc ignores or that we don't expect to be stow packages
NOT_STOW_PACKAGES='^(linux|windows|atuin|README\.md|install\.(sh|ps1)|setup\.(sh|ps1)|test\.ps1|check-drift\.sh|\.stowrc|\.gitignore|\.git)$'

DRIFT_LINES=()
TOTAL_DRIFT=0

section() {
    local title=$1 count=$2 body=$3
    [[ $count -eq 0 ]] && return 0
    TOTAL_DRIFT=$((TOTAL_DRIFT + count))
    DRIFT_LINES+=("$count $title")
    [[ -n $QUIET ]] && return 0
    printf "\n=== %s (%d) ===\n" "$title" "$count"
    printf "%s\n" "$body" | sed 's/^/  /'
}

# Extract a bash array literal from setup.sh by name → newline-separated values
extract_array() {
    local name=$1
    awk -v name="$name" '
        $0 ~ "^"name"=\\(" { capture=1; sub("^"name"=\\(","") }
        capture {
            sub(/[ \t]*#.*$/, "")  # strip end-of-line comments
            sub(/\)[ \t]*$/, "")   # strip closing paren
            print
        }
        capture && /\)/ { capture=0 }
    ' "$REPO/setup.sh" | tr -s ' \t\n' '\n' | sed '/^$/d' | sort -u
}

count_lines() { [[ -z $1 ]] && echo 0 || echo "$1" | wc -l; }

# -----------------------------------------------------------------------------
# 1. Brew leaves vs Brewfile
# -----------------------------------------------------------------------------
if command -v brew &>/dev/null && [[ -f $REPO/linux/Brewfile ]]; then
    installed=$(brew leaves 2>/dev/null | awk -F/ '{print $NF}' | sort -u)
    tracked=$(awk -F'"' '/^brew "/ {print $2}' "$REPO/linux/Brewfile" \
              | awk -F/ '{print $NF}' | sort -u)
    drift=$(comm -23 <(echo "$installed") <(echo "$tracked") || true)
    section "brew packages not in Brewfile" "$(count_lines "$drift")" "$drift"
fi

# -----------------------------------------------------------------------------
# 2. Bun globals vs BUN_GLOBALS array
# -----------------------------------------------------------------------------
if command -v bun &>/dev/null; then
    installed=$(bun pm ls -g 2>/dev/null \
                | sed -nE 's/^[├└]── (@?[^@]+)@.*/\1/p' | sort -u)
    tracked=$(extract_array BUN_GLOBALS)
    drift=$(comm -23 <(echo "$installed") <(echo "$tracked") || true)
    section "bun globals not in BUN_GLOBALS" "$(count_lines "$drift")" "$drift"
fi

# -----------------------------------------------------------------------------
# 3. uv tools vs UV_TOOLS array
# -----------------------------------------------------------------------------
if command -v uv &>/dev/null; then
    # `uv tool list` prints "<tool> v<version>" for each top-level tool
    installed=$(uv tool list 2>/dev/null \
                | awk '/^[a-zA-Z]/ {print $1}' | sort -u)
    tracked=$(extract_array UV_TOOLS)
    drift=$(comm -23 <(echo "$installed") <(echo "$tracked") || true)
    section "uv tools not in UV_TOOLS" "$(count_lines "$drift")" "$drift"
fi

# -----------------------------------------------------------------------------
# 4. gh extensions vs GH_EXTENSIONS array
# -----------------------------------------------------------------------------
if command -v gh &>/dev/null; then
    installed=$(gh extension list 2>/dev/null \
                | awk '{ for(i=1;i<=NF;i++) if($i ~ /^[^[:space:]]+\/[^[:space:]]+$/) {print $i; break} }' \
                | sort -u)
    tracked=$(extract_array GH_EXTENSIONS)
    drift=$(comm -23 <(echo "$installed") <(echo "$tracked") || true)
    section "gh extensions not in GH_EXTENSIONS" "$(count_lines "$drift")" "$drift"
fi

# -----------------------------------------------------------------------------
# 5. Dotfiles packages that aren't symlinked into ~/.config (forgot to stow?)
# -----------------------------------------------------------------------------
unstowed=""
for entry in "$REPO"/*; do
    name=${entry##*/}
    [[ $name =~ $NOT_STOW_PACKAGES ]] && continue
    target=$HOME/.config/$name
    if [[ -L $target ]]; then
        [[ "$(readlink -f "$target")" == "$entry" ]] && continue   # correctly stowed
        unstowed+="$name (symlink points elsewhere)"$'\n'
    elif [[ -e $target ]]; then
        unstowed+="$name (real path at ~/.config/$name — use \`stow --adopt $name\`)"$'\n'
    else
        unstowed+="$name (not stowed — run \`cd ~/dotfiles && stow $name\`)"$'\n'
    fi
done
unstowed=${unstowed%$'\n'}
section "dotfiles packages not stowed" "$(count_lines "$unstowed")" "$unstowed"

# -----------------------------------------------------------------------------
# 6. Real (non-symlink) dirs in ~/.config with NO matching dotfiles entry
#    Capped at 10 — there's always a long tail of app-default configs you
#    don't actually want to track. This surfaces candidates for triage.
# -----------------------------------------------------------------------------
candidates=""
count=0
for d in "$HOME"/.config/*/; do
    [[ -L ${d%/} ]] && continue
    name=$(basename "$d")
    [[ -e "$REPO/$name" ]] && continue
    candidates+="$name"$'\n'
    count=$((count + 1))
    [[ $count -ge 10 ]] && break
done
candidates=${candidates%$'\n'}
section "untracked ~/.config dirs (potential new dotfiles, top 10)" "$(count_lines "$candidates")" "$candidates"

# -----------------------------------------------------------------------------
# 7. Uncommitted changes in the dotfiles repo working tree
# -----------------------------------------------------------------------------
if [[ -d $REPO/.git ]]; then
    porcelain=$(git -C "$REPO" status --porcelain 2>/dev/null | head -20)
    [[ -n $porcelain ]] && section "uncommitted dotfiles changes (run \`cd ~/dotfiles && git status\`)" \
        "$(count_lines "$porcelain")" "$porcelain"

    # -------------------------------------------------------------------------
    # 8. Local commits not yet pushed to origin
    # -------------------------------------------------------------------------
    if git -C "$REPO" rev-parse --abbrev-ref '@{u}' &>/dev/null; then
        ahead=$(git -C "$REPO" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
        if [[ $ahead -gt 0 ]]; then
            ahead_log=$(git -C "$REPO" log --oneline '@{u}..HEAD' 2>/dev/null)
            section "unpushed dotfiles commits (run \`cd ~/dotfiles && git push\`)" \
                "$ahead" "$ahead_log"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
if [[ $TOTAL_DRIFT -eq 0 ]]; then
    [[ -z $QUIET ]] && echo "✓ No drift detected."
    exit 0
fi

if [[ -n $QUIET ]]; then
    printf -v summary '%s, ' "${DRIFT_LINES[@]}"
    summary=${summary%, }
    printf "[dotfiles drift] %s — run \`~/dotfiles/check-drift.sh\` for details\n" "$summary"
fi
exit 1
