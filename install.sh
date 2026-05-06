#!/usr/bin/env bash
# install.sh — cold-start installer for the Linux side of the dotfiles.
#
# Real run:
#   curl -fsSL https://raw.githubusercontent.com/slamb2k/dotfiles/main/install.sh | bash
#
# Dry run (preview without making changes):
#   curl -fsSL https://raw.githubusercontent.com/slamb2k/dotfiles/main/install.sh | bash -s -- --dry-run
#
# Local invocation:
#   ./install.sh [--dry-run]
#
# What it does:
#   1. Installs Homebrew if missing
#   2. Adds brew to the current shell PATH
#   3. Clones / updates the repo to ~/dotfiles
#   4. Hands off to ./setup.sh (passing through any flags)
#
# Idempotent. Safe to re-run.

set -euo pipefail

DRY_RUN=
for arg in "$@"; do
  case $arg in
    -n|--dry-run) DRY_RUN=1 ;;
  esac
done

section() {
  if [[ -n $DRY_RUN ]]; then printf "\n[dry-run] === %s ===\n" "$1"
  else                       printf "\n=== %s ===\n" "$1"
  fi
}
note()  { printf "  %s\n" "$*"; }
would() { printf "  would: %s\n" "$*"; }

# -----------------------------------------------------------------------------
# 1. Homebrew
# -----------------------------------------------------------------------------
if command -v brew &>/dev/null; then
    section "Homebrew"; note "already installed at $(command -v brew)"
elif [[ -n $DRY_RUN ]]; then
    section "Homebrew"; would "install via official curl-bash installer"
else
    section "Installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Activate brew in this shell session (dry-run included so PATH lookups work)
if [[ -d /home/linuxbrew/.linuxbrew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true
elif [[ -d /opt/homebrew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# 2. Git (Ubuntu has it pre-installed; brew variant is newer if needed)
# -----------------------------------------------------------------------------
if command -v git &>/dev/null; then
    :
elif [[ -n $DRY_RUN ]]; then
    section "git"; would "brew install git"
else
    section "Installing git"; brew install git
fi

# -----------------------------------------------------------------------------
# 3. Clone or update the repo
# -----------------------------------------------------------------------------
repo="$HOME/dotfiles"
if [[ ! -d $repo ]]; then
    if [[ -n $DRY_RUN ]]; then
        section "$repo"; would "git clone https://github.com/slamb2k/dotfiles.git $repo"
        note "(can't dry-run setup.sh without the repo — skipping step 4)"
        echo
        echo '[dry-run] No changes made. Re-run without --dry-run to apply.'
        exit 0
    fi
    section "Cloning to $repo"
    git clone https://github.com/slamb2k/dotfiles.git "$repo"
else
    section "Updating $repo"
    if [[ -n $DRY_RUN ]]; then
        would "git -C $repo pull --rebase --autostash"
    else
        git -C "$repo" pull --rebase --autostash
    fi
fi

# -----------------------------------------------------------------------------
# 4. Hand off to setup.sh (forwarding flags)
# -----------------------------------------------------------------------------
section "Running ~/dotfiles/setup.sh $*"
cd "$repo"
exec ./setup.sh "$@"
