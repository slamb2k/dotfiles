#!/usr/bin/env bash
# install.sh — cold-start installer for the Linux side of the dotfiles.
#
# Run on a fresh Ubuntu / WSL Ubuntu install:
#   curl -fsSL https://raw.githubusercontent.com/slamb2k/dotfiles/main/install.sh | bash
#
# What it does:
#   1. Installs Homebrew if missing
#   2. Adds brew to the current shell PATH
#   3. Clones / updates the repo to ~/dotfiles
#   4. Hands off to ./setup.sh (which runs brew bundle, stow, mise, apt, etc.)
#
# Idempotent. Safe to re-run.

set -euo pipefail

section() { printf "\n=== %s ===\n" "$1"; }

# -----------------------------------------------------------------------------
# 1. Homebrew
# -----------------------------------------------------------------------------
if ! command -v brew &>/dev/null; then
    section "Installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Activate brew in this shell session
if [[ -d /home/linuxbrew/.linuxbrew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -d /opt/homebrew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# -----------------------------------------------------------------------------
# 2. Git (Ubuntu has it pre-installed; brew variant is newer if needed)
# -----------------------------------------------------------------------------
if ! command -v git &>/dev/null; then
    section "Installing git"
    brew install git
fi

# -----------------------------------------------------------------------------
# 3. Clone or update the repo
# -----------------------------------------------------------------------------
repo="$HOME/dotfiles"
if [[ ! -d $repo ]]; then
    section "Cloning to $repo"
    git clone https://github.com/slamb2k/dotfiles.git "$repo"
else
    section "Updating $repo"
    git -C "$repo" pull --rebase --autostash
fi

# -----------------------------------------------------------------------------
# 4. Hand off to setup.sh
# -----------------------------------------------------------------------------
section "Running ~/dotfiles/setup.sh"
cd "$repo"
exec ./setup.sh
