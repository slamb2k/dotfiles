#!/usr/bin/env bash
# ~/dotfiles/setup.sh
#
# Restore the WSL/Linux side of the dev box, or check it for drift.
#
# Usage:
#   ./setup.sh                 # apply everything (real run)
#   ./setup.sh --dry-run       # show what would change, make no modifications
#   ./setup.sh --check         # dotfiles convergence check (repo manifests/stow/git state)
#   ./setup.sh --check -q      # one-line convergence summary (silent when clean)
#   ./setup.sh --check --fix   # interactive convergence fixer (per-item prompts)
#   ./setup.sh --audit         # read-only tool hygiene audit (duplicates/legacy/unmanaged)
#   ./setup.sh --save          # auto-commit local changes, pull --rebase, push
#   ./setup.sh -h              # this help text
#
# Idempotent. Safe to re-run.
set -euo pipefail

# Keep setup/stow/perl quiet even before zsh has loaded 00-env.zsh.
export LANG=${LANG:-C.UTF-8}
if ! locale -a 2>/dev/null | grep -qx "${LANG}"; then
  export LANG=C.UTF-8
fi

# -----------------------------------------------------------------------------
# Args
# -----------------------------------------------------------------------------
DRY_RUN=
CHECK=
QUIET=
FIX=
AUDIT=
SAVE=
for arg in "$@"; do
  case $arg in
    -n|--dry-run) DRY_RUN=1 ;;
    -c|--check)   CHECK=1 ;;
    -q|--quiet)   QUIET=1 ;;
    --fix)        FIX=1 ;;
    --audit)      AUDIT=1 ;;
    -s|--save)    SAVE=1 ;;
    -h|--help)    sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

# Sanity: --fix is interactive and requires --check.
if [[ -n $FIX && -z $CHECK ]]; then
  echo "Error: --fix requires --check" >&2; exit 1
fi
if [[ -n $FIX && -n $QUIET ]]; then
  echo "Error: --fix is interactive — cannot combine with --quiet" >&2; exit 1
fi
if [[ -n $SAVE && ( -n $CHECK || -n $FIX || -n $AUDIT ) ]]; then
  echo "Error: --save cannot combine with --check / --fix / --audit" >&2; exit 1
fi
if [[ -n $AUDIT && ( -n $CHECK || -n $FIX ) ]]; then
  echo "Error: --audit cannot combine with --check / --fix" >&2; exit 1
fi

section() {
  if [[ -n $DRY_RUN ]]; then printf "\n[dry-run] === %s ===\n" "$1"
  else                       printf "\n=== %s ===\n" "$1"
  fi
}
note()  { printf "  %s\n" "$*"; }
would() { printf "  would: %s\n" "$*"; }

# True on WSL — used to skip installs the Windows host already provides.
is_wsl() { [[ -n ${WSL_DISTRO_NAME:-} ]] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; }

# -----------------------------------------------------------------------------
# Helper: install a tool from its own apt repository.
#   install_apt_repo <name> <key_url> <repo_line> [packages]
# -----------------------------------------------------------------------------
install_apt_repo() {
  local name=$1
  local key_url=$2
  local repo_line=$3
  local packages=${4:-$name}
  local keyring="/etc/apt/keyrings/${name}.gpg"

  if command -v "$name" &>/dev/null; then
    note "$name already installed, skipping"
    return 0
  fi

  if [[ -n $DRY_RUN ]]; then
    would "register $name apt repo ($repo_line) and apt install $packages"
    return 0
  fi

  sudo install -d -m 0755 /etc/apt/keyrings
  if [[ $key_url == *.asc ]]; then
    curl -fsSL "$key_url" | sudo gpg --dearmor --yes -o "$keyring"
  else
    sudo curl -fsSL "$key_url" -o "$keyring"
  fi
  sudo chmod a+r "$keyring"
  echo "deb [signed-by=$keyring] $repo_line" \
    | sudo tee "/etc/apt/sources.list.d/${name}.list" >/dev/null
  sudo apt update
  sudo apt install -y $packages
}

# -----------------------------------------------------------------------------
# Drift detection (run via --check). Compares the live machine against the
# manifests in this repo (Brewfile, linux/*.txt tool manifests, stow packages,
# claude config symlinks, dotfiles repo state).
#
# With --check --fix, walks each drift item interactively and offers
# type-specific actions (track in manifest, uninstall, stow, adopt, ignore).
# -----------------------------------------------------------------------------
REPO=$(cd "$(dirname "$0")" && pwd)

# Colors (TTY only) — used by both check and fix
C_RESET= C_BOLD= C_DIM= C_RED= C_GREEN= C_YELLOW= C_CYAN=
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
fi

# Manifest helpers. Manifest files are newline-separated, with blank lines and
# comments ignored. setup.sh owns logic; linux/*.txt files own install inventory.
manifest_items() {
  local file=$1
  [[ -f $file ]] || return 0
  sed -E 's/[[:space:]]*#.*$//; /^[[:space:]]*$/d; s/^[[:space:]]+//; s/[[:space:]]+$//' "$file" | sort -u
}

add_to_manifest() {
  local file=$1 item=$2
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if manifest_items "$file" | grep -Fxq "$item"; then
    return 0
  fi
  printf '%s\n' "$item" >> "$file"
  # Keep comments at top and sort non-comment entries below them.
  local tmp; tmp=$(mktemp)
  { grep -E '^[[:space:]]*#' "$file" || true; manifest_items "$file"; } > "$tmp"
  mv "$tmp" "$file"
}

# Drift collectors — populated by run_drift_check, consumed by run_drift_fix.
DRIFT_BREW=() DRIFT_BUN=() DRIFT_UV=() DRIFT_GH=()
DRIFT_UNSTOWED=()        # entries: "name|state"  state ∈ {missing,real-path,symlink-elsewhere}
DRIFT_CLAUDE_SYMLINK=()  # entries: "rel|state"   state ∈ {missing,real-file,symlink-elsewhere}
DRIFT_ADOPT=()           # entries: "skills/foo"
DRIFT_CLAUDE_LOCKS=()    # entries: "id|state"     state ∈ {missing,broken,drift}
DRIFT_CONFIG_DIRS=()     # entries: "name"         (untracked ~/.config/<name>)
DRIFT_UNCOMMITTED_COUNT=0
DRIFT_UNPUSHED_COUNT=0

# Section registry — populated at run_drift_fix start in the order sections will
# run. Each fix_X bumps CURRENT_SECTION_IDX and updates SECTION_STATUS so the
# rolling list above the body shows progress (▶ current · ☑ done · ⏸ skipped).
SECTION_EMOJIS=()
SECTION_TITLES=()
SECTION_STATUS=()  # pending | current | done | skipped
CURRENT_SECTION_IDX=-1

run_drift_check() {
  local NOT_STOW_PACKAGES='^(linux|windows|atuin|claude|README\.md|install\.(sh|ps1)|setup\.(sh|ps1)|test\.ps1|\.stowrc|\.gitignore|\.git)$'
  local DRIFT_LINES=()
  local TOTAL_DRIFT=0

  # drift_section <title> <count> <body> [emoji] [color]
  drift_section() {
    local title=$1 count=$2 body=$3 emoji=${4:-⚠️} color=${5:-$C_YELLOW}
    [[ $count -eq 0 ]] && return 0
    TOTAL_DRIFT=$((TOTAL_DRIFT + count))
    DRIFT_LINES+=("$count $title")
    [[ -n $QUIET ]] && return 0
    printf "\n%s%s %s%s%s %s(%d)%s\n" \
      "$color" "$emoji" "$C_BOLD" "$title" "$C_RESET" "$C_DIM" "$count" "$C_RESET"
    printf "%s\n" "$body" | sed 's/^/  /'
  }

  [[ -z $QUIET ]] && printf "%s%s🔍 Dotfiles drift check%s\n" "$C_BOLD" "$C_CYAN" "$C_RESET"

  count_lines() { [[ -z $1 ]] && echo 0 || echo "$1" | wc -l; }

  # 1. Brew leaves vs Brewfile
  if command -v brew &>/dev/null && [[ -f $REPO/linux/Brewfile ]]; then
    local installed tracked drift
    installed=$(brew leaves 2>/dev/null | awk -F/ '{print $NF}' | sort -u)
    tracked=$(awk -F'"' '/^brew "/ {print $2}' "$REPO/linux/Brewfile" \
              | awk -F/ '{print $NF}' | sort -u)
    drift=$(comm -23 <(echo "$installed") <(echo "$tracked") || true)
    [[ -n $drift ]] && while IFS= read -r p; do DRIFT_BREW+=("$p"); done <<< "$drift"
    drift_section "brew packages not in Brewfile" "$(count_lines "$drift")" "$drift" "📦" "$C_YELLOW"
  fi

  # 2. Bun globals vs linux/bun-globals.txt
  if command -v bun &>/dev/null; then
    local installed tracked drift
    installed=$(bun pm ls -g 2>/dev/null \
                | sed -nE 's/^[├└]── (@?[^@]+)@.*/\1/p' | sort -u)
    tracked=$(manifest_items "$REPO/linux/bun-globals.txt")
    drift=$(comm -23 <(echo "$installed") <(echo "$tracked") || true)
    [[ -n $drift ]] && while IFS= read -r p; do DRIFT_BUN+=("$p"); done <<< "$drift"
    drift_section "bun globals not in linux/bun-globals.txt" "$(count_lines "$drift")" "$drift" "🥟" "$C_YELLOW"
  fi

  # 3. uv tools vs linux/uv-tools.txt
  if command -v uv &>/dev/null; then
    local installed tracked drift
    installed=$(uv tool list 2>/dev/null \
                | awk '/^[a-zA-Z]/ {print $1}' | sort -u)
    tracked=$(manifest_items "$REPO/linux/uv-tools.txt")
    drift=$(comm -23 <(echo "$installed") <(echo "$tracked") || true)
    [[ -n $drift ]] && while IFS= read -r p; do DRIFT_UV+=("$p"); done <<< "$drift"
    drift_section "uv tools not in linux/uv-tools.txt" "$(count_lines "$drift")" "$drift" "🐍" "$C_YELLOW"
  fi

  # 4. gh extensions vs linux/gh-extensions.txt
  if command -v gh &>/dev/null; then
    local installed tracked drift
    installed=$(gh extension list 2>/dev/null \
                | awk '{ for(i=1;i<=NF;i++) if($i ~ /^[^[:space:]]+\/[^[:space:]]+$/) {print $i; break} }' \
                | sort -u)
    tracked=$(manifest_items "$REPO/linux/gh-extensions.txt")
    drift=$(comm -23 <(echo "$installed") <(echo "$tracked") || true)
    [[ -n $drift ]] && while IFS= read -r p; do DRIFT_GH+=("$p"); done <<< "$drift"
    drift_section "gh extensions not in linux/gh-extensions.txt" "$(count_lines "$drift")" "$drift" "🐙" "$C_YELLOW"
  fi

  # 5. Dotfiles packages that aren't represented under ~/.config.
  #    Stow may either replace ~/.config/<package> with a directory symlink OR
  #    leave a real directory containing per-file symlinks, especially when the
  #    app writes runtime state beside managed config. Treat both as stowed.
  package_files_stowed() {
    local entry=$1 name=${entry##*/} f rel target
    local found=0
    while IFS= read -r -d '' f; do
      found=1
      rel=${f#$entry/}
      target="$HOME/.config/$name/$rel"
      if [[ -e $target ]]; then
        # Accept either a direct file symlink or a path that traverses a
        # symlinked parent directory; both resolve to the managed repo file.
        [[ "$(readlink -f "$target")" == "$(readlink -f "$f")" ]] || return 1
      else
        return 1
      fi
    done < <(find "$entry" -type f -print0)
    [[ $found -eq 1 ]]
  }

  local unstowed=""
  for entry in "$REPO"/*; do
    local name=${entry##*/}
    [[ $name =~ $NOT_STOW_PACKAGES ]] && continue
    local target=$HOME/.config/$name
    if [[ -L $target ]]; then
      [[ "$(readlink -f "$target")" == "$entry" ]] && continue
      unstowed+="$name (symlink points elsewhere)"$'\n'
      DRIFT_UNSTOWED+=("$name|symlink-elsewhere")
    elif [[ -e $target ]]; then
      if [[ -d $target ]] && package_files_stowed "$entry"; then
        continue
      fi
      unstowed+="$name (real path at ~/.config/$name with unmanaged/mislinked package files — use \`stow --adopt $name\` or fix symlinks)"$'\n'
      DRIFT_UNSTOWED+=("$name|real-path")
    else
      unstowed+="$name (not stowed — run \`cd ~/dotfiles && stow $name\`)"$'\n'
      DRIFT_UNSTOWED+=("$name|missing")
    fi
  done
  unstowed=${unstowed%$'\n'}
  drift_section "dotfiles packages not stowed" "$(count_lines "$unstowed")" "$unstowed" "🔗" "$C_RED"

  # 6. Claude package-specific drift. The Claude package owns its own
  #    validation rules because settings/skills/plugins have app-specific
  #    semantics that do not belong in the top-level orchestrator.
  local claude_symlinks="" claude_adopt="" claude_locks=""
  if [[ -x $REPO/claude/validate.sh ]]; then
    local type id state message
    while IFS=$'\t' read -r type id state message; do
      [[ -z ${type:-} ]] && continue
      case $type in
        symlink)
          claude_symlinks+="$message"$'\n'
          DRIFT_CLAUDE_SYMLINK+=("$id|$state")
          ;;
        adopt)
          claude_adopt+="$message"$'\n'
          DRIFT_ADOPT+=("$id")
          ;;
        lock)
          claude_locks+="$message"$'\n'
          DRIFT_CLAUDE_LOCKS+=("$id|$state")
          ;;
      esac
    done < <(DOTFILES_REPO="$REPO" "$REPO/claude/validate.sh")
  fi
  claude_symlinks=${claude_symlinks%$'\n'}
  drift_section "claude config symlinks broken" "$(count_lines "$claude_symlinks")" "$claude_symlinks" "💔" "$C_RED"
  claude_adopt=${claude_adopt%$'\n'}
  drift_section "claude adoption candidates (mv into ~/dotfiles/claude/.claude/<sub>/ + restow, or add to ~/dotfiles/.adopt-ignore)" \
    "$(count_lines "$claude_adopt")" "$claude_adopt" "🆕" "$C_CYAN"
  claude_locks=${claude_locks%$'\n'}
  drift_section "claude reproducibility locks" "$(count_lines "$claude_locks")" "$claude_locks" "🔒" "$C_YELLOW"

  # 9. Real (non-symlink) dirs in ~/.config with no matching dotfiles entry.
  #    Capped at 10 — there's always a long tail of app-default configs.
  #    Filterable via ~/dotfiles/.config-ignore (one name or glob per line).
  local CONFIG_IGNORE_FILE="$REPO/.config-ignore"
  is_config_ignored() {
    [[ -f $CONFIG_IGNORE_FILE ]] || return 1
    local name=$1 pattern
    while IFS= read -r pattern; do
      [[ -z $pattern || $pattern == \#* ]] && continue
      # shellcheck disable=SC2053
      [[ $name == $pattern ]] && return 0
    done < "$CONFIG_IGNORE_FILE"
    return 1
  }
  local candidates="" count=0
  for d in "$HOME"/.config/*/; do
    [[ -L ${d%/} ]] && continue
    local name; name=$(basename "$d")
    [[ -e "$REPO/$name" ]] && continue
    is_config_ignored "$name" && continue
    candidates+="$name"$'\n'
    DRIFT_CONFIG_DIRS+=("$name")
    count=$((count + 1))
    [[ $count -ge 10 ]] && break
  done
  candidates=${candidates%$'\n'}
  drift_section "untracked ~/.config dirs (potential new dotfiles, top 10)" "$(count_lines "$candidates")" "$candidates" "📁" "$C_DIM"

  # 10. Uncommitted changes in the dotfiles repo working tree
  if [[ -d $REPO/.git ]]; then
    local porcelain
    # Collapse git's two-char XY status to a single status character —
    # prefer the working-tree side, fall back to the index side. So
    # " M setup.sh", "M  setup.sh", and "MM setup.sh" all render as "M setup.sh".
    porcelain=$(git -C "$REPO" status --porcelain 2>/dev/null | head -20 | awk '{
      x = substr($0,1,1); y = substr($0,2,1)
      c = (y != " ") ? y : x
      print c " " substr($0,4)
    }')
    if [[ -n $porcelain ]]; then
      DRIFT_UNCOMMITTED_COUNT=$(count_lines "$porcelain")
      drift_section "uncommitted dotfiles changes (run \`cd ~/dotfiles && git status\`)" \
        "$DRIFT_UNCOMMITTED_COUNT" "$porcelain" "📝" "$C_YELLOW"
    fi

    # 11. Local commits not yet pushed to origin
    if git -C "$REPO" rev-parse --abbrev-ref '@{u}' &>/dev/null; then
      local ahead ahead_log
      ahead=$(git -C "$REPO" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
      if [[ $ahead -gt 0 ]]; then
        ahead_log=$(git -C "$REPO" log --oneline '@{u}..HEAD' 2>/dev/null)
        DRIFT_UNPUSHED_COUNT=$ahead
        drift_section "unpushed dotfiles commits (run \`cd ~/dotfiles && git push\`)" \
          "$ahead" "$ahead_log" "📤" "$C_YELLOW"
      fi
    fi
  fi

  # Summary
  if [[ $TOTAL_DRIFT -eq 0 ]]; then
    [[ -z $QUIET ]] && printf "%s✅ No drift detected.%s\n" "$C_GREEN" "$C_RESET"
    return 0
  fi
  if [[ -n $QUIET ]]; then
    local summary
    printf -v summary '%s, ' "${DRIFT_LINES[@]}"
    summary=${summary%, }
    printf "%s⚠️ [dotfiles drift]%s %s — run \`~/dotfiles/setup.sh --check\` for details\n" \
      "$C_YELLOW" "$C_RESET" "$summary"
  else
    printf "\n%s%s⚠️ %d total drift item(s) found.%s\n" "$C_BOLD" "$C_YELLOW" "$TOTAL_DRIFT" "$C_RESET"
  fi
  return 1
}

# -----------------------------------------------------------------------------
# Interactive drift fix mode (run via --check --fix). Per drift type, opens
# fzf with all items: ↑↓ to navigate, Tab to multi-select, Enter applies the
# default action to selected items, Ctrl-X applies the alternative action,
# Esc skips the type. Requires fzf.
# -----------------------------------------------------------------------------
say_ok()   { printf "    %s✓️ %s%s\n" "$C_GREEN"  "$*" "$C_RESET"; }
say_dim()  { printf "    %s%s%s\n"   "$C_DIM"    "$*" "$C_RESET"; }
say_warn() { printf "    %s⚠️ %s%s\n" "$C_YELLOW" "$*" "$C_RESET"; }

# Draw a dim horizontal rule that fills the terminal width.
draw_rule() {
  local w; w=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
  [[ -z $w || $w -lt 1 ]] && w=80
  local r; printf -v r '─%.0s' $(seq 1 "$w")
  printf "%s%s%s\n" "$C_DIM" "$r" "$C_RESET"
}

# Print the boxed "Interactive fix mode" sign — the top of the persistent
# header that stays in place while sections rotate below.
print_sign() {
  printf "%s┌─────────────────────────┐%s\n" "$C_BOLD" "$C_RESET"
  printf "%s│ 🔧 Interactive fix mode │%s\n" "$C_BOLD" "$C_RESET"
  printf "%s└─────────────────────────┘%s\n" "$C_BOLD" "$C_RESET"
}

# Append a section to the registry. Order here determines the order of the
# rolling status list and must match the call order of fix_section/fix_*.
register_section() {
  SECTION_EMOJIS+=("$1")
  SECTION_TITLES+=("$2")
  SECTION_STATUS+=("pending")
}

# Print the per-section status list shown above the active section's body.
render_section_list() {
  local i status title
  for i in "${!SECTION_TITLES[@]}"; do
    status=${SECTION_STATUS[$i]}
    title=${SECTION_TITLES[$i]}
    case $status in
      current) printf " 👉 %s\n" "$title" ;;
      done)    printf " ✔️ %s\n" "$title" ;;
      skipped) printf " ❌ %s. %s(skipped)%s\n" "$title" "$C_DIM" "$C_RESET" ;;
      *)       printf " 🔹 %s\n" "$title" ;;
    esac
  done
}

# Restore cursor to the position saved after the sign was printed and erase to
# end-of-screen. Everything above the cursor (drift report + sign) stays put;
# everything below is wiped so the next section can paint from a clean canvas.
reset_body() {
  tput rc 2>/dev/null || printf '\033[u'
  tput ed 2>/dev/null || printf '\033[J'
}

# Begin a new section: bump the index, mark this entry current, repaint the body.
begin_section() {
  CURRENT_SECTION_IDX=$((CURRENT_SECTION_IDX + 1))
  SECTION_STATUS[$CURRENT_SECTION_IDX]="current"
  reset_body
  render_section_list
  printf "\n"
}

add_to_brewfile() { printf 'brew "%s"\n' "$1" >> "$REPO/linux/Brewfile"; }

# ----- action verbs (one per type × direction) -----
do_brew_track()  { add_to_brewfile "$1" && say_ok "tracked $1"; }
do_brew_remove() { brew uninstall "$1" 2>&1 | sed 's/^/    /' || say_warn "uninstall $1 failed"; }
do_bun_track()   { add_to_manifest "$REPO/linux/bun-globals.txt" "$1" && say_ok "tracked $1"; }
do_bun_remove()  { bun remove -g "$1" 2>&1 | sed 's/^/    /' || say_warn "remove $1 failed"; }
do_uv_track()    { add_to_manifest "$REPO/linux/uv-tools.txt" "$1" && say_ok "tracked $1"; }
do_uv_remove()   { uv tool uninstall "$1" 2>&1 | sed 's/^/    /' || say_warn "remove $1 failed"; }
do_gh_track()    { add_to_manifest "$REPO/linux/gh-extensions.txt" "$1" && say_ok "tracked $1"; }
do_gh_remove()   { gh extension remove "$1" 2>&1 | sed 's/^/    /' || say_warn "remove $1 failed"; }

do_unstowed_fix() {
  local entry=$1 name=${entry%%|*} state=${entry##*|}
  case $state in
    missing)           (cd "$REPO" && stow .) && say_ok "stowed repo configs" || say_warn "stow . failed" ;;
    real-path)         say_warn "$name is a real path; back it up/adopt manually, then run: cd ~/dotfiles && stow ." ;;
    symlink-elsewhere) rm -f "$HOME/.config/$name" && (cd "$REPO" && stow .) && say_ok "fixed $name" || say_warn "fix $name failed" ;;
  esac
}

# Stow the home-targeted claude package, then delegate mutable Claude-specific
# reconciliation to the package-local apply script.
stow_claude() {
  stow --target="$HOME" -d "$REPO" claude || return 1
  [[ -x "$REPO/claude/apply.sh" ]] && bash "$REPO/claude/apply.sh" >/dev/null
  return 0
}

do_claude_fix() {
  local entry=$1 rel=${entry%%|*} state=${entry##*|}
  DOTFILES_REPO="$REPO" "$REPO/claude/fix.sh" symlink "$rel" "$state" default
}

do_adopt() {
  DOTFILES_REPO="$REPO" "$REPO/claude/fix.sh" adopt "$1" candidate default
}

do_adopt_ignore() {
  DOTFILES_REPO="$REPO" "$REPO/claude/fix.sh" adopt "$1" candidate ignore
}

do_claude_lock_fix() {
  local entry=$1 id=${entry%%|*} state=${entry##*|}
  DOTFILES_REPO="$REPO" "$REPO/claude/fix.sh" lock "$id" "$state" default
}

do_config_adopt() {
  local name=$1
  # Whole-dir symlink convention (matches existing packages like zshrc).
  # `stow` would create per-file symlinks at ~/.config/<file>, leaking
  # the package's contents into ~/.config root.
  mv "$HOME/.config/$name" "$REPO/$name" \
    && ln -s "$REPO/$name" "$HOME/.config/$name" \
    && say_ok "adopted $name (review with: cd ~/dotfiles && git diff)" \
    || say_warn "adopt $name failed"
}

do_config_ignore() {
  printf "%s\n" "$1" >> "$REPO/.config-ignore"
  say_ok "added $1 to .config-ignore"
}

# y/n prompt for whole-section actions (not multi-select). Returns 0=yes, 1=no.
prompt_yn() {
  local prompt=$1 default=${2:-y} hint
  if [[ $default == y ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
  printf "  %s %s%s%s " "$prompt" "$C_DIM" "$hint" "$C_RESET" >&2
  local ans
  read -r ans < /dev/tty
  ans=${ans:-$default}
  [[ ${ans,,} == y* ]]
}

# Build a commit message from the dotfiles repo's current dirty state.
# Format: "chore: <prefix> <YYYY-MM-DD HH:MM> — <up-to-3 paths>[, +N more]"
# Returns 1 if working tree is clean. Echoes message on stdout.
gen_commit_msg() {
  local prefix=$1
  local porcelain count stamp files
  porcelain=$(cd "$REPO" && git status --porcelain 2>/dev/null)
  [[ -z $porcelain ]] && return 1
  count=$(printf '%s\n' "$porcelain" | wc -l)
  stamp=$(date '+%Y-%m-%d %H:%M')
  # Column 4+ to handle paths with spaces; cap at 3 + "+N more" for long tails.
  files=$(printf '%s\n' "$porcelain" | awk '{print substr($0,4)}' | head -3 | paste -sd, - | sed 's/,/, /g')
  [[ $count -gt 3 ]] && files="$files, +$((count - 3)) more"
  printf 'chore: %s %s — %s\n' "$prefix" "$stamp" "$files"
}

fix_uncommitted() {
  [[ $DRIFT_UNCOMMITTED_COUNT -eq 0 ]] && return 0
  begin_section
  printf "%s📝 Processing %d Uncommitted dotfiles changes%s\n" \
    "$C_BOLD" "$DRIFT_UNCOMMITTED_COUNT" "$C_RESET"
  draw_rule
  printf "\n"

  (cd "$REPO" && git -c color.status=always status) 2>&1 | sed 's/^/    /' | head -40

  local msg
  msg=$(gen_commit_msg "drift sync")
  printf "  %sCommit message:%s %s\n" "$C_DIM" "$C_RESET" "$msg"

  if prompt_yn "Commit, pull --rebase, push?" n; then
    run_save "drift sync" 2>&1 | sed 's/^/    /'
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
      say_ok "synced"
    else
      say_warn "sync failed — check output above"
    fi
    SECTION_STATUS[$CURRENT_SECTION_IDX]="done"
  else
    SECTION_STATUS[$CURRENT_SECTION_IDX]="skipped"
  fi
}

fix_unpushed() {
  [[ $DRIFT_UNPUSHED_COUNT -eq 0 ]] && return 0
  begin_section
  printf "%s📤 Processing %d Unpushed dotfiles commits%s\n" \
    "$C_BOLD" "$DRIFT_UNPUSHED_COUNT" "$C_RESET"
  draw_rule
  printf "\n"

  if prompt_yn "Run \`git pull --rebase && git push\`?" y; then
    run_save 2>&1 | sed 's/^/    /'
    SECTION_STATUS[$CURRENT_SECTION_IDX]="done"
  else
    SECTION_STATUS[$CURRENT_SECTION_IDX]="skipped"
  fi
}

# ----- fzf-driven multi-select picker -----
# bulk_select <prompt> <default_label> <alt_key|""> <alt_label|""> -- <items...>
# Echoes "default\n<items>" or "alt\n<items>" on confirm; nothing on Esc.
# (No title — section title is already printed by fix_section above the picker.)
bulk_select() {
  local prompt=$1 default_label=$2 alt_key=$3 alt_label=$4
  shift 4
  [[ ${1:-} == "--" ]] && shift
  local items=("$@")
  [[ ${#items[@]} -eq 0 ]] && return 0

  # Build hint, then print it OUTSIDE fzf so it sits at col 0 (above the
  # picker area) with a blank line separating it from the items.
  local hint expect_arg=()
  if [[ -n $alt_key && -n $alt_label ]]; then
    hint="↑↓/Ctrl-JK navigate · Tab multi-select · Enter ${default_label} · Ctrl-X ${alt_label} · Esc skip"
    expect_arg=(--expect="$alt_key")
  else
    hint="↑↓/Ctrl-JK navigate · Tab multi-select · Enter ${default_label} · Esc skip"
  fi
  printf "%s%s%s\n" "$C_DIM" "$hint" "$C_RESET" >&2

  # fzf gets only items. The default pointer slot gives them their 2-space
  # visual indent (pointer at col 0, item text at col 2). --height=~ shrinks
  # the picker to fit content for short lists.
  local result rc=0
  result=$(printf '%s\n' "${items[@]}" | fzf --multi \
    --reverse \
    --height=~50% \
    --no-input \
    --no-info \
    --no-separator \
    --header="" \
    --margin=0,0,0,1 \
    --gutter=' ' \
    --pointer="➜ " \
    --marker="✓ " \
    --bind='ctrl-j:down,ctrl-k:up' \
    "${expect_arg[@]}") || rc=$?
  [[ $rc -ne 0 ]] && return 0

  local key="" items_out=""
  if [[ ${#expect_arg[@]} -gt 0 ]]; then
    key=$(printf '%s' "$result" | head -n1)
    items_out=$(printf '%s' "$result" | tail -n +2)
  else
    items_out="$result"
  fi
  [[ -z $items_out ]] && return 0

  if [[ -z $key ]]; then printf "default\n"
  else                   printf "alt\n"
  fi
  printf '%s\n' "$items_out"
}

# fix_section <title> <prompt> <emoji> <def_label> <def_fn> <alt_key> <alt_label> <alt_fn> <items...>
fix_section() {
  local title=$1 prompt=$2 emoji=$3
  local def_label=$4 def_fn=$5
  local alt_key=$6 alt_label=$7 alt_fn=$8
  shift 8
  local items=("$@")
  [[ ${#items[@]} -eq 0 ]] && return 0

  begin_section
  printf "%s%s Processing %d %s%s\n" \
    "$C_BOLD" "$emoji" "${#items[@]}" "$title" "$C_RESET"
  draw_rule

  local result
  result=$(bulk_select "$prompt" "$def_label" "$alt_key" "$alt_label" -- "${items[@]}")
  if [[ -z $result ]]; then
    SECTION_STATUS[$CURRENT_SECTION_IDX]="skipped"
    return 0
  fi

  local action picks
  action=$(printf '%s' "$result" | head -n1)
  picks=$(printf '%s' "$result" | tail -n +2)

  while IFS= read -r item; do
    [[ -z $item ]] && continue
    case $action in
      default) "$def_fn" "$item" ;;
      alt)     "$alt_fn" "$item" ;;
    esac
  done <<< "$picks"

  SECTION_STATUS[$CURRENT_SECTION_IDX]="done"
}

run_drift_fix() {
  local total=$((${#DRIFT_BREW[@]} + ${#DRIFT_BUN[@]} + ${#DRIFT_UV[@]} + ${#DRIFT_GH[@]} \
               + ${#DRIFT_UNSTOWED[@]} + ${#DRIFT_CLAUDE_SYMLINK[@]} + ${#DRIFT_ADOPT[@]} \
               + ${#DRIFT_CLAUDE_LOCKS[@]} + ${#DRIFT_CONFIG_DIRS[@]} \
               + DRIFT_UNCOMMITTED_COUNT + DRIFT_UNPUSHED_COUNT))
  if [[ $total -eq 0 ]]; then return 0; fi
  if [[ ! -t 0 ]]; then
    printf "%s⚠️ --fix requires an interactive terminal.%s\n" "$C_YELLOW" "$C_RESET" >&2
    return 1
  fi
  if ! command -v fzf &>/dev/null; then
    printf "%s⚠️ --fix requires fzf for navigation/multiselect.%s\n" "$C_YELLOW" "$C_RESET" >&2
    printf "  Install: %sbrew install fzf%s\n" "$C_BOLD" "$C_RESET" >&2
    return 1
  fi

  # Reset registry each run so reruns start clean.
  SECTION_EMOJIS=()
  SECTION_TITLES=()
  SECTION_STATUS=()
  CURRENT_SECTION_IDX=-1

  # Pre-register sections in the order they'll be processed below. Only
  # sections with items show up — must stay in lockstep with the fix_* calls.
  [[ ${#DRIFT_BREW[@]} -gt 0 ]]           && register_section "📦" "Brew packages not in Brewfile"
  [[ ${#DRIFT_BUN[@]} -gt 0 ]]            && register_section "🥟" "Bun globals not in linux/bun-globals.txt"
  [[ ${#DRIFT_UV[@]} -gt 0 ]]             && register_section "🐍" "uv tools not in linux/uv-tools.txt"
  [[ ${#DRIFT_GH[@]} -gt 0 ]]             && register_section "🐙" "gh extensions not in linux/gh-extensions.txt"
  [[ ${#DRIFT_UNSTOWED[@]} -gt 0 ]]       && register_section "🔗" "Stow packages"
  [[ ${#DRIFT_CLAUDE_SYMLINK[@]} -gt 0 ]] && register_section "💔" "Claude config symlinks"
  [[ ${#DRIFT_ADOPT[@]} -gt 0 ]]          && register_section "🆕" "Claude adoption candidates"
  [[ ${#DRIFT_CLAUDE_LOCKS[@]} -gt 0 ]]   && register_section "🔒" "Claude reproducibility locks"
  [[ ${#DRIFT_CONFIG_DIRS[@]} -gt 0 ]]    && register_section "📁" "Untracked ~/.config dirs"
  [[ $DRIFT_UNCOMMITTED_COUNT -gt 0 ]]    && register_section "📝" "Uncommitted dotfiles changes"
  [[ $DRIFT_UNPUSHED_COUNT -gt 0 ]]       && register_section "📤" "Unpushed dotfiles commits"

  # Print the sign below the drift report, then save the cursor so each
  # section's begin_section can clear-and-repaint just the body below it.
  printf "\n"
  print_sign
  printf "\n"
  tput sc 2>/dev/null || printf '\033[s'

  fix_section "Brew packages not in Brewfile"      "brew"   "📦" \
    "Track in Brewfile"      do_brew_track  "ctrl-x" "Uninstall"              do_brew_remove   "${DRIFT_BREW[@]}"
  fix_section "Bun globals not in linux/bun-globals.txt"     "bun"    "🥟" \
    "Track in bun-globals.txt"   do_bun_track   "ctrl-x" "Uninstall"              do_bun_remove    "${DRIFT_BUN[@]}"
  fix_section "uv tools not in linux/uv-tools.txt"           "uv"     "🐍" \
    "Track in uv-tools.txt"      do_uv_track    "ctrl-x" "Uninstall"              do_uv_remove     "${DRIFT_UV[@]}"
  fix_section "gh extensions not in linux/gh-extensions.txt" "gh"     "🐙" \
    "Track in gh-extensions.txt" do_gh_track    "ctrl-x" "Uninstall"              do_gh_remove     "${DRIFT_GH[@]}"
  fix_section "Stow packages"                      "stow"   "🔗" \
    "Auto-fix (stow / adopt as needed)"  do_unstowed_fix  "" "" "" "${DRIFT_UNSTOWED[@]}"
  fix_section "Claude config symlinks"             "claude" "💔" \
    "Auto-fix (restore symlinks)"        do_claude_fix    "" "" "" "${DRIFT_CLAUDE_SYMLINK[@]}"
  fix_section "Claude adoption candidates"         "adopt"  "🆕" \
    "Adopt into dotfiles"    do_adopt       "ctrl-x" "Ignore (.adopt-ignore)" do_adopt_ignore  "${DRIFT_ADOPT[@]}"
  fix_section "Claude reproducibility locks"       "locks"  "🔒" \
    "Generate/fix lock"      do_claude_lock_fix "" "" "" "${DRIFT_CLAUDE_LOCKS[@]}"
  fix_section "Untracked ~/.config dirs"           "config" "📁" \
    "Adopt into dotfiles (mv + stow)" do_config_adopt "ctrl-x" "Ignore (.config-ignore)" do_config_ignore "${DRIFT_CONFIG_DIRS[@]}"

  fix_uncommitted
  fix_unpushed

  # Final view: clear body, show the final section list, then completion line.
  reset_body
  render_section_list
  printf "\n%s🚩 Fix mode complete.%s Re-run %s./setup.sh --check%s to confirm.\n" \
    "$C_GREEN" "$C_RESET" "$C_BOLD" "$C_RESET"
}

# -----------------------------------------------------------------------------
# --audit: read-only package/tool hygiene audit. Complements --check by looking
# for duplicate command providers across brew/apt/npm/bun/pnpm/manual installs,
# legacy tools, unmanaged apt-only utilities, and shell framework leftovers. It
# never removes anything.
# -----------------------------------------------------------------------------
run_audit() {
  local cmd path pkg mark

  printf "%s%s🧭 Redundant tool audit%s\n" "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf "%sRead-only: this reports candidates only; it does not uninstall anything.%s\n" "$C_DIM" "$C_RESET"

  printf "\n%sActive package managers%s\n" "$C_BOLD" "$C_RESET"
  for cmd in brew apt npm pnpm bun pip pip3 pipx cargo gem go; do
    if command -v "$cmd" &>/dev/null; then
      printf "  ✓ %-6s %s\n" "$cmd" "$($cmd --version 2>/dev/null | head -1 || true)"
    else
      printf "  · %-6s not found\n" "$cmd"
    fi
  done

  printf "\n%sPATH precedence%s\n" "$C_BOLD" "$C_RESET"
  tr ':' '\n' <<< "$PATH" | nl -ba | sed -n '1,30p'

  printf "\n%sDuplicate command providers in PATH%s\n" "$C_BOLD" "$C_RESET"
  local commands=(
    git gh curl wget rg ripgrep fd fdfind fzf bat batcat eza tree jq yq tmux nvim
    starship zoxide atuin direnv az kubectl terraform helm k9s lazygit lazydocker
    delta dust duf procs hyperfine shellcheck shfmt bats go rustup uv uvx ruff
    pre-commit http xh nmap stow glow gum pandoc ffmpeg magick yt-dlp
  )
  local dup_count=0
  for cmd in "${commands[@]}"; do
    mapfile -t paths < <(which -a "$cmd" 2>/dev/null | awk '!seen[$0]++')
    if (( ${#paths[@]} > 1 )); then
      dup_count=$((dup_count + 1))
      printf "  %s⚠ %s%s\n" "$C_YELLOW" "$cmd" "$C_RESET"
      printf '    %s\n' "${paths[@]}"
    fi
  done
  [[ $dup_count -eq 0 ]] && printf "  %s✓ no duplicate command providers found%s\n" "$C_GREEN" "$C_RESET"

  printf "\n%sApt packages that duplicate Brew-managed tools%s\n" "$C_BOLD" "$C_RESET"
  local apt_candidates=(git gh curl wget jq tmux azure-cli nmap fd)
  local apt_count=0
  for pkg in "${apt_candidates[@]}"; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
      apt_count=$((apt_count + 1))
      mark=$(apt-mark showmanual 2>/dev/null | grep -qx "$pkg" && echo manual || echo auto/dependency)
      printf "  %-12s %s\n" "$pkg" "$mark"
      if command -v apt-get &>/dev/null; then
        local removals
        removals=$(apt-get -s remove "$pkg" 2>/dev/null \
          | awk '/^The following packages will be REMOVED:/{flag=1; next} flag && /^[[:space:]]/{print; next} flag{exit}' \
          | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')
        [[ -n $removals ]] && printf "    would remove: %s\n" "$removals"
      fi
    fi
  done
  [[ $apt_count -eq 0 ]] && printf "  %s✓ no apt duplicates from candidate list%s\n" "$C_GREEN" "$C_RESET"

  printf "\n%sUser/manual install leftovers%s\n" "$C_BOLD" "$C_RESET"
  local leftovers=0
  for path in "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx" "$HOME/.zcompdump" "$HOME/.p10k.zsh" "$HOME/.zshrc"; do
    if [[ -e $path ]]; then
      leftovers=$((leftovers + 1))
      printf "  ⚠ %s\n" "$path"
    fi
  done
  [[ -d $HOME/.oh-my-zsh ]] && { leftovers=$((leftovers + 1)); printf "  ⚠ %s (legacy; not loaded by ZDOTDIR)\n" "$HOME/.oh-my-zsh"; }
  [[ -d /usr/local/go ]] && { leftovers=$((leftovers + 1)); printf "  ⚠ /usr/local/go (manual/root-owned Go; Brew Go should win)\n"; }
  [[ -f /usr/local/bin/starship ]] && { leftovers=$((leftovers + 1)); printf "  ⚠ /usr/local/bin/starship (manual; Brew starship should win)\n"; }
  [[ $leftovers -eq 0 ]] && printf "  %s✓ no known manual leftovers found%s\n" "$C_GREEN" "$C_RESET"

  printf "\n%sLegacy/unmanaged tools%s\n" "$C_BOLD" "$C_RESET"
  local legacy_count=0
  local legacy_tools=(
    neofetch screenfetch fastfetch
    pyenv rbenv asdf fnm
    powerlevel10k p10k
  )
  for cmd in "${legacy_tools[@]}"; do
    if command -v "$cmd" &>/dev/null; then
      legacy_count=$((legacy_count + 1))
      printf "  ⚠ %s -> %s\n" "$cmd" "$(command -v "$cmd")"
      if command -v dpkg-query &>/dev/null; then
        local owner
        owner=$(dpkg-query -S "$(command -v "$cmd")" 2>/dev/null | cut -d: -f1 | head -1 || true)
        [[ -n $owner ]] && printf "    apt package: %s\n" "$owner"
      fi
    fi
  done
  local legacy_config_dirs=(neofetch fastfetch screenfetch)
  for cfg in "${legacy_config_dirs[@]}"; do
    if [[ -d "$HOME/.config/$cfg" ]]; then
      legacy_count=$((legacy_count + 1))
      printf "  ⚠ config dir: %s\n" "$HOME/.config/$cfg"
    fi
  done
  [[ -d $HOME/.oh-my-zsh ]] && { legacy_count=$((legacy_count + 1)); printf "  ⚠ shell framework: %s\n" "$HOME/.oh-my-zsh"; }
  [[ -f $HOME/.p10k.zsh ]] && { legacy_count=$((legacy_count + 1)); printf "  ⚠ prompt config: %s\n" "$HOME/.p10k.zsh"; }
  if [[ $legacy_count -eq 0 ]]; then
    printf "  %s✓ no known legacy/unmanaged tools found%s\n" "$C_GREEN" "$C_RESET"
  else
    printf "  Suggestions:\n"
    printf "    - If unused: remove apt-only legacy tools, e.g. sudo apt remove neofetch\n"
    printf "    - Remove matching config dirs only after confirming they are obsolete.\n"
  fi

  printf "\n%sGlobal JavaScript tools%s\n" "$C_BOLD" "$C_RESET"
  if command -v npm &>/dev/null; then
    printf "  npm -g:\n"
    npm -g ls --depth=0 2>/dev/null | sed 's/^/    /' || true
  fi
  if command -v pnpm &>/dev/null; then
    printf "  pnpm -g:\n"
    pnpm list -g --depth=0 2>/dev/null | sed 's/^/    /' || true
  fi
  if command -v bun &>/dev/null; then
    printf "  bun -g:\n"
    bun pm ls -g 2>/dev/null | sed 's/^/    /' || true
  fi

  printf "\n%sManual binaries in /usr/local/bin%s\n" "$C_BOLD" "$C_RESET"
  if [[ -d /usr/local/bin ]]; then
    find /usr/local/bin -maxdepth 1 \( -type f -o -type l \) 2>/dev/null \
      | sort | sed 's#^#  #' | head -100
  else
    printf "  /usr/local/bin does not exist\n"
  fi

  printf "\n%sNext steps%s\n" "$C_BOLD" "$C_RESET"
  printf "  1. Prefer Brew for tools listed in linux/Brewfile.\n"
  printf "  2. Do not apt-remove packages whose simulation removes ubuntu-wsl/byobu.\n"
  printf "  3. Treat --check as repo convergence and --audit as machine/tool hygiene.\n"
  printf "  4. Root-owned leftovers require sudo, e.g. /usr/local/go or ~/.oh-my-zsh.\n"
}

# -----------------------------------------------------------------------------
# --save: non-interactive sync. Auto-commits any local changes (with a
# generated message), pulls with --rebase, and pushes. Designed to be
# aliased and run anytime. Honors --dry-run and --quiet.
# -----------------------------------------------------------------------------
run_save() {
  local prefix=${1:-save}
  cd "$REPO" || return 1
  if [[ ! -d .git ]]; then
    echo "Error: $REPO is not a git repository" >&2; return 1
  fi

  local has_upstream=0
  git rev-parse --abbrev-ref '@{u}' &>/dev/null && has_upstream=1

  # 1. Commit local changes (if any) with auto-generated message.
  local msg count
  if msg=$(gen_commit_msg "$prefix"); then
    count=$(git status --porcelain 2>/dev/null | wc -l)

    if [[ -n $DRY_RUN ]]; then
      [[ -z $QUIET ]] && printf "[dry-run] would commit (%d file(s)):\n  %s\n" "$count" "$msg"
    else
      [[ -z $QUIET ]] && printf "%s📝 Committing %d file(s):%s %s\n" "$C_BOLD" "$count" "$C_RESET" "$msg"
      git add -A && git -c color.ui=always commit -m "$msg" >/dev/null \
        || { echo "commit failed" >&2; return 1; }
    fi
  fi

  # 2. Pull with rebase (skip if no upstream — usually a brand-new branch).
  if [[ $has_upstream -eq 0 ]]; then
    [[ -z $QUIET ]] && printf "%s⚠️  No upstream tracking branch — skipping pull/push.%s\n" "$C_YELLOW" "$C_RESET"
    return 0
  fi
  if [[ -n $DRY_RUN ]]; then
    [[ -z $QUIET ]] && printf "[dry-run] would: git pull --rebase\n"
  else
    [[ -z $QUIET ]] && printf "%s⬇️  Pulling…%s\n" "$C_BOLD" "$C_RESET"
    git pull --rebase --autostash 2>&1 | sed 's/^/  /' \
      || { echo "pull failed — resolve conflicts then re-run" >&2; return 1; }
  fi

  # 3. Push if there's anything ahead of upstream.
  local ahead
  ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  if [[ $ahead -eq 0 ]]; then
    [[ -z $QUIET ]] && printf "%s✅ In sync with origin.%s\n" "$C_GREEN" "$C_RESET"
    return 0
  fi
  if [[ -n $DRY_RUN ]]; then
    [[ -z $QUIET ]] && printf "[dry-run] would: git push (%d commit(s) ahead)\n" "$ahead"
  else
    [[ -z $QUIET ]] && printf "%s⬆️  Pushing %d commit(s)…%s\n" "$C_BOLD" "$ahead" "$C_RESET"
    git push 2>&1 | sed 's/^/  /' || { echo "push failed" >&2; return 1; }
    [[ -z $QUIET ]] && printf "%s✅ Saved.%s\n" "$C_GREEN" "$C_RESET"
  fi
}

# Short-circuit: --audit runs the duplicate/redundant tool audit and exits.
if [[ -n $AUDIT ]]; then
  run_audit
  exit $?
fi

# Short-circuit: --save syncs the dotfiles repo and exits.
if [[ -n $SAVE ]]; then
  run_save
  exit $?
fi

# Short-circuit: --check runs the drift report (and optional --fix) and exits.
if [[ -n $CHECK ]]; then
  # Clear screen on first run for a clean canvas (interactive TTY only).
  [[ -z $QUIET && -t 1 ]] && { tput clear 2>/dev/null || printf '\033[2J\033[H'; }
  rc=0
  run_drift_check || rc=$?
  if [[ -n $FIX ]]; then
    run_drift_fix || true
  fi
  exit "$rc"
fi

# Existing-machine hint for normal setup runs. Non-blocking by design: fresh
# machines should proceed, but lived-in machines get nudged toward diagnostics.
existing_machine_hint() {
  [[ -n ${DOTFILES_NO_EXISTING_MACHINE_HINT:-} ]] && return 0
  [[ -n $DRY_RUN ]] && return 0

  local signals=()
  [[ -f $HOME/.zshenv ]] && signals+=("~/.zshenv exists")
  [[ -e $HOME/.config/zshrc ]] && signals+=("~/.config/zshrc exists")
  [[ -f $HOME/.zshrc ]] && signals+=("legacy ~/.zshrc exists")
  command -v brew &>/dev/null && signals+=("Homebrew already installed")
  [[ -d $HOME/.config && $(find "$HOME/.config" -mindepth 1 -maxdepth 1 2>/dev/null | head -1) ]] \
    && signals+=("~/.config is populated")

  [[ ${#signals[@]} -eq 0 ]] && return 0

  printf "\n%s%s⚠ Existing machine detected%s\n" "$C_BOLD" "$C_YELLOW" "$C_RESET"
  printf "  Signals: %s\n" "${signals[*]}"
  printf "  Recommended before applying setup:\n"
  printf "    %s~/dotfiles/setup.sh --check%s\n" "$C_BOLD" "$C_RESET"
  printf "    %s~/dotfiles/setup.sh --dry-run%s\n" "$C_BOLD" "$C_RESET"
  printf "  Continuing anyway. Set DOTFILES_NO_EXISTING_MACHINE_HINT=1 to suppress.\n"
}

existing_machine_hint

# -----------------------------------------------------------------------------
# 1. Homebrew
# -----------------------------------------------------------------------------
section 'Homebrew'
if command -v brew &>/dev/null; then
  note "brew already installed at $(command -v brew)"
elif [[ -n $DRY_RUN ]]; then
  would 'install Homebrew via official curl-bash installer'
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# -----------------------------------------------------------------------------
# 2. Brewfile
# -----------------------------------------------------------------------------
section 'Brewfile packages'
BREWFILE="$(dirname "$0")/linux/Brewfile"
if [[ -n $DRY_RUN ]]; then
  if command -v brew &>/dev/null; then
    brew bundle check --verbose --file="$BREWFILE" || true
  else
    note "(brew not installed yet — would install everything in $BREWFILE)"
  fi
else
  brew bundle --file="$BREWFILE"
fi

# -----------------------------------------------------------------------------
# 3. Stow configs into ~/.config (per .stowrc)
# -----------------------------------------------------------------------------
section 'Stow symlinks'
cd "$(dirname "$0")"
if [[ -n $DRY_RUN ]]; then
  stow -nv . 2>&1 | sed 's/^/  /'
else
  stow .
fi

# -----------------------------------------------------------------------------
# 4. zsh ZDOTDIR bootstrap
# -----------------------------------------------------------------------------
section 'zsh ZDOTDIR pointer'
if [[ -f ~/.zshenv ]]; then
  note '~/.zshenv already exists'
elif [[ -n $DRY_RUN ]]; then
  would 'write ~/.zshenv with ZDOTDIR=$HOME/.config/zshrc'
else
  echo 'export ZDOTDIR="$HOME/.config/zshrc"' > ~/.zshenv
fi

# -----------------------------------------------------------------------------
# 5. Language runtimes via mise
# -----------------------------------------------------------------------------
section 'mise runtimes'
MISE_CFG="$(dirname "$0")/mise/config.toml"
if ! command -v mise &>/dev/null; then
  note '(mise not installed yet — install via Brewfile first)'
elif [[ -n $DRY_RUN ]]; then
  would "mise trust $MISE_CFG"
  mise ls --current 2>&1 | sed 's/^/  /' || true
else
  # Trust the repo's mise config so subsequent `mise install` / `mise ls` don't error
  mise trust "$MISE_CFG" 2>/dev/null || true
  # Skip node GPG signature verification: brew gpg 2.5.19 can't talk to system
  # keyboxd 2.4.4, so verification fails even with the signing key imported.
  # HTTPS + SHA256 checksum still apply.
  MISE_NODE_VERIFY=false mise install
fi

# Make tools installed under $HOME visible to the rest of this script:
#   - mise shims expose bun/node/python/go (for the bun + playwright sections)
#   - ~/.local/bin holds claude (Claude Code installer drops it here)
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

# =============================================================================
# Non-brew installs
# =============================================================================

# -----------------------------------------------------------------------------
# apt — system / kernel-adjacent / GUI deps
# -----------------------------------------------------------------------------
section 'apt packages (system / GUI deps)'
APT_PKGS=(
  build-essential ca-certificates curl wget gnupg software-properties-common
  apt-transport-https openssh-server unzip zip lsof tcpdump dnsutils usbutils
  adb android-tools-adb
  bats fonts-noto-color-emoji fonts-liberation fonts-freefont-ttf
  fonts-ipafont-gothic fonts-tlwg-loma-otf fonts-unifont fonts-wqy-zenhei
  xfonts-cyrillic xfonts-scalable xvfb
  libffi-dev python3-dev openjdk-17-jdk
  libasound2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64
  libcairo2 libcairo-gobject2 libcups2t64 libdbus-1-3 libdrm2 libenchant-2-2
  libepoxy0 libevent-2.1-7t64 libflite1 libfontconfig1 libfreetype6 libgbm1
  libgdk-pixbuf-2.0-0 libgles2 libglib2.0-0t64 libgstreamer1.0-0
  libgstreamer-gl1.0-0 libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-base1.0-0
  libgtk-3-0t64 libgtk-4-1 libharfbuzz0b libharfbuzz-icu0 libhyphen0
  libicu74 libjpeg-turbo8 liblcms2-2 libmanette-0.2-0 libnspr4 libnss3 libopus0
  libpango-1.0-0 libpangocairo-1.0-0 libpng16-16t64 libsecret-1-0 libvpx9
  libwayland-client0 libwayland-egl1 libwayland-server0 libwebp7 libwebpdemux2
  libwoff1 libx11-6 libx11-xcb1 libx264-164 libxcb1 libxcb-shm0 libxcomposite1
  libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxkbcommon0 libxml2
  libxrandr2 libxrender1 libxshmfence1 libxslt1.1
  gstreamer1.0-libav gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-good
  ubuntu-wsl
)
if [[ -n $DRY_RUN ]]; then
  missing=$(sudo apt-get install --simulate -y "${APT_PKGS[@]}" 2>/dev/null \
              | grep '^Inst ' | awk '{print $2}' || true)
  if [[ -z $missing ]]; then
    note '(all configured apt packages already installed)'
  else
    note 'would install:'
    echo "$missing" | sed 's/^/    /'
  fi
else
  sudo apt update && sudo apt install -y "${APT_PKGS[@]}"
fi

# -----------------------------------------------------------------------------
# Docker Engine on Linux (NOT Docker Desktop — that's the Windows side)
# Follow https://docs.docker.com/engine/install/ubuntu/
# Then: sudo usermod -aG docker $USER && newgrp docker
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Tailscale  https://tailscale.com/kb/1031/install-linux
# Skipped on WSL — the Windows host runs Tailscale and the WSL distro inherits
# the tunnel. Installed on bare-metal/VM Linux dev machines.
# -----------------------------------------------------------------------------
section 'Tailscale'
if is_wsl; then
  note 'WSL detected — skipping (Windows host handles Tailscale)'
else
  install_apt_repo tailscale \
    "https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg" \
    "https://pkgs.tailscale.com/stable/ubuntu noble main"
  if command -v tailscale &>/dev/null; then
    if [[ -n $DRY_RUN ]]; then
      would 'sudo tailscale up'
    else
      sudo tailscale up
    fi
  fi
fi

# -----------------------------------------------------------------------------
# NVIDIA CUDA toolkit (Windows driver passes through to WSL)
# https://docs.nvidia.com/cuda/wsl-user-guide/
# -----------------------------------------------------------------------------
section 'NVIDIA CUDA toolkit'
if dpkg -l nvidia-cuda-toolkit &>/dev/null; then
  note 'nvidia-cuda-toolkit already installed'
elif [[ -n $DRY_RUN ]]; then
  would 'sudo apt install -y nvidia-cuda-toolkit'
else
  sudo apt install -y nvidia-cuda-toolkit
fi

# -----------------------------------------------------------------------------
# PowerShell 7 on Linux
# -----------------------------------------------------------------------------
section 'PowerShell 7'
if command -v pwsh &>/dev/null; then
  note "pwsh already installed: $(pwsh --version)"
elif [[ -n $DRY_RUN ]]; then
  would 'register Microsoft apt repo + apt install -y powershell'
else
  sudo apt install -y wget apt-transport-https software-properties-common
  wget -q https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb
  sudo dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb
  sudo apt update && sudo apt install -y powershell
fi

# -----------------------------------------------------------------------------
# Claude Code
# -----------------------------------------------------------------------------
section 'Claude Code'
if command -v claude &>/dev/null; then
  note "claude already installed at $(command -v claude)"
elif [[ -n $DRY_RUN ]]; then
  would 'curl -fsSL https://claude.ai/install.sh | bash'
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

# -----------------------------------------------------------------------------
# Claude Code config (stowed into $HOME, not ~/.config)
# -----------------------------------------------------------------------------
section 'Claude Code config'
if [[ ! -d ~/dotfiles/claude ]]; then
  note '(no claude package in dotfiles — skipping)'
elif [[ -n $DRY_RUN ]]; then
  stow -nv --target="$HOME" -d "$HOME/dotfiles" claude 2>&1 | sed 's/^/  /'
  would "bash $HOME/dotfiles/claude/apply.sh"
else
  mkdir -p ~/.claude
  stow_claude
fi

# -----------------------------------------------------------------------------
# bun globals
# -----------------------------------------------------------------------------
section 'bun globals'
mapfile -t BUN_GLOBALS < <(manifest_items "$REPO/linux/bun-globals.txt")
if ! command -v bun &>/dev/null; then
  note '(bun not installed yet — install via Brewfile or curl-bash first)'
elif [[ ${#BUN_GLOBALS[@]} -eq 0 ]]; then
  note 'no bun globals tracked'
elif [[ -n $DRY_RUN ]]; then
  installed=$(bun pm ls -g 2>/dev/null | tr -d ' \t' || true)
  for pkg in "${BUN_GLOBALS[@]}"; do
    if [[ $installed == *"$pkg@"* ]]; then
      note "$pkg installed"
    else
      would "bun install -g $pkg"
    fi
  done
else
  bun install -g "${BUN_GLOBALS[@]}"
fi

# -----------------------------------------------------------------------------
# gh extensions
# -----------------------------------------------------------------------------
section 'gh extensions'
mapfile -t GH_EXTENSIONS < <(manifest_items "$REPO/linux/gh-extensions.txt")
if ! command -v gh &>/dev/null; then
  note '(gh not installed yet — install via Brewfile first)'
elif [[ ${#GH_EXTENSIONS[@]} -eq 0 ]]; then
  note 'no gh extensions tracked'
elif [[ -n $DRY_RUN ]]; then
  ext_list=$(gh extension list 2>/dev/null || true)
  for ext in "${GH_EXTENSIONS[@]}"; do
    short=${ext##*/}
    if [[ $ext_list == *"$short"* ]]; then
      note "$ext installed"
    else
      would "gh extension install $ext"
    fi
  done
else
  for ext in "${GH_EXTENSIONS[@]}"; do
    gh extension install "$ext" --force 2>/dev/null || true
  done
fi

# -----------------------------------------------------------------------------
# uv tools
# -----------------------------------------------------------------------------
section 'uv tools'
mapfile -t UV_TOOLS < <(manifest_items "$REPO/linux/uv-tools.txt")
if ! command -v uv &>/dev/null; then
  note '(uv not installed yet — install via Brewfile first)'
elif [[ ${#UV_TOOLS[@]} -eq 0 ]]; then
  note 'no uv tools tracked'
elif [[ -n $DRY_RUN ]]; then
  uv_list=$(uv tool list 2>/dev/null || true)
  for tool in "${UV_TOOLS[@]}"; do
    if [[ $uv_list == *"$tool"* ]]; then
      note "$tool installed"
    else
      would "uv tool install $tool"
    fi
  done
else
  for tool in "${UV_TOOLS[@]}"; do
    uv tool install "$tool" || true
  done
fi

# -----------------------------------------------------------------------------
# ngrok  https://ngrok.com/docs/agent/#linux  (Linuxbrew has no cask)
# -----------------------------------------------------------------------------
section 'ngrok'
install_apt_repo ngrok \
  "https://ngrok-agent.s3.amazonaws.com/ngrok.asc" \
  "https://ngrok-agent.s3.amazonaws.com bookworm main"

# === gh (GitHub CLI) — uncomment if you prefer GitHub's apt repo over brew ===
# install_apt_repo gh \
#   "https://cli.github.com/packages/githubcli-archive-keyring.gpg" \
#   "https://cli.github.com/packages stable main"

# -----------------------------------------------------------------------------
# Playwright browsers
# -----------------------------------------------------------------------------
section 'Playwright browsers'
if [[ -d ~/.cache/ms-playwright && -n $(ls -A ~/.cache/ms-playwright 2>/dev/null) ]]; then
  note 'Playwright browsers already in ~/.cache/ms-playwright'
elif [[ -n $DRY_RUN ]]; then
  would 'bunx playwright install chromium firefox webkit'
elif command -v bunx &>/dev/null; then
  bunx playwright install chromium firefox webkit
else
  note '(bun not installed yet — skipping)'
fi

# -----------------------------------------------------------------------------
# Final stow re-run (legacy belt-and-braces; no-op if step 3 already ran)
# -----------------------------------------------------------------------------
if [[ -z $DRY_RUN ]]; then
  cd ~/dotfiles && stow . 2>/dev/null || true
fi

echo
if [[ -n $DRY_RUN ]]; then
  echo '[dry-run] No changes made. Re-run without --dry-run to apply.'
else
  echo 'Done. Restart your shell.'
fi
