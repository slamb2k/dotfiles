#!/usr/bin/env bash
# ~/dotfiles/setup.sh
set -euo pipefail

# -----------------------------------------------------------------------------
# Helper: install a tool from its own apt repository.
#   install_apt_repo <name> <key_url> <repo_line> [packages]
#   - <name>       used for keyring filename, sources.list filename, and the
#                  default `command -v` skip-check / package name
#   - <key_url>    URL to the GPG key; *.asc is dearmored, else copied as-is
#   - <repo_line>  the part after `deb [signed-by=...]`, e.g.
#                    "https://pkgs.tailscale.com/stable/ubuntu noble main"
#   - [packages]   optional; defaults to <name>
# -----------------------------------------------------------------------------
install_apt_repo() {
  local name=$1
  local key_url=$2
  local repo_line=$3
  local packages=${4:-$name}
  local keyring="/etc/apt/keyrings/${name}.gpg"

  if command -v "$name" &>/dev/null; then
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

# 1. Install Homebrew if absent
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# 2. Install everything in the Brewfile
brew bundle --file="$(dirname "$0")/linux/Brewfile"

# 3. Stow configs into ~/.config (per omer's pattern)
cd "$(dirname "$0")"
stow .

# 4. Bootstrap zsh's ZDOTDIR pointer (from earlier conversation)
if [[ ! -f ~/.zshenv ]]; then
  echo 'export ZDOTDIR="$HOME/.config/zshrc"' > ~/.zshenv
fi

# 5. Install language runtimes
mise install


# =============================================================================
# Non-brew installs (manual checklist — NOT executed by `brew bundle`)
# =============================================================================

# === apt (Ubuntu) — system / kernel-adjacent / GUI deps ===
   sudo apt update && sudo apt install -y \
     build-essential ca-certificates curl wget gnupg software-properties-common \
     apt-transport-https openssh-server unzip zip lsof tcpdump dnsutils usbutils \
     adb android-tools-adb \
     bats fonts-noto-color-emoji fonts-liberation fonts-freefont-ttf \
     fonts-ipafont-gothic fonts-tlwg-loma-otf fonts-unifont fonts-wqy-zenhei \
     xfonts-cyrillic xfonts-scalable xvfb \
     libffi-dev python3-dev openjdk-17-jdk \
     libasound2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
     libcairo2 libcairo-gobject2 libcups2t64 libdbus-1-3 libdrm2 libenchant-2-2 \
     libepoxy0 libevent-2.1-7t64 libflite1 libfontconfig1 libfreetype6 libgbm1 \
     libgdk-pixbuf-2.0-0 libgles2 libglib2.0-0t64 libgstreamer1.0-0 \
     libgstreamer-gl1.0-0 libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-base1.0-0 \
     libgtk-3-0t64 libgtk-4-1 libharfbuzz0b libharfbuzz-icu0 libhyphen0 \
     libicu74 libjpeg-turbo8 liblcms2-2 libmanette-0.2-0 libnspr4 libnss3 libopus0 \
     libpango-1.0-0 libpangocairo-1.0-0 libpng16-16t64 libsecret-1-0 libvpx9 \
     libwayland-client0 libwayland-egl1 libwayland-server0 libwebp7 libwebpdemux2 \
     libwoff1 libx11-6 libx11-xcb1 libx264-164 libxcb1 libxcb-shm0 libxcomposite1 \
     libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxkbcommon0 libxml2 \
     libxrandr2 libxrender1 libxshmfence1 libxslt1.1 \
     gstreamer1.0-libav gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
     ubuntu-wsl

# === Docker Engine on Linux (NOT Docker Desktop — that's the Windows side) ===
# Follow https://docs.docker.com/engine/install/ubuntu/ — adds /etc/apt/sources.list.d/docker.list
# Then: sudo usermod -aG docker $USER && newgrp docker

# === Tailscale === https://tailscale.com/kb/1031/install-linux
install_apt_repo tailscale \
  "https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg" \
  "https://pkgs.tailscale.com/stable/ubuntu noble main"
sudo tailscale up

# === NVIDIA CUDA (Windows driver passes through; install toolkit inside WSL) ===
# https://docs.nvidia.com/cuda/wsl-user-guide/ — apt repo for ubuntu2404
   sudo apt install nvidia-cuda-toolkit
# Verify: nvidia-smi && nvcc --version

# === PowerShell 7 on Linux ===
   sudo apt install -y wget apt-transport-https software-properties-common
   wget -q https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb
   sudo dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb
   sudo apt update && sudo apt install -y powershell

# === Claude Code (Anthropic) ===
# Currently installed at ~/.local/share/claude/versions/2.1.128 (binary).
# To restore: official installer per docs.anthropic.com/claude/code, or
   curl -fsSL https://claude.ai/install.sh | bash

# === Bun globals to reinstall (after bun is on PATH) ===
   bun install -g \
     @google/clasp \
     @steipete/bird \
     clawdhub \
     happy-dom \
     markdown-pdf \
     marked \
     mcporter \
     md-to-pdf \
     pdfkit \
     playwright \
     puppeteer-core

# === gh extensions to reinstall ===
   GH_EXTENSIONS=(
     dlvhdr/gh-dash
     github/gh-copilot
   )
   for ext in "${GH_EXTENSIONS[@]}"; do
     gh extension install "$ext" --force 2>/dev/null || true
   done

# === uv tools to reinstall ===
   uv tool install graphifyy
   uv tool install nano-pdf

# === ngrok === https://ngrok.com/docs/agent/#linux  (Linuxbrew has no cask)
install_apt_repo ngrok \
  "https://ngrok-agent.s3.amazonaws.com/ngrok.asc" \
  "https://ngrok-agent.s3.amazonaws.com bookworm main"

# === gh (GitHub CLI) — uncomment if you prefer GitHub's apt repo over brew ===
# install_apt_repo gh \
#   "https://cli.github.com/packages/githubcli-archive-keyring.gpg" \
#   "https://cli.github.com/packages stable main"

# === Playwright browsers (Bun/npm package "playwright" needs browser binaries) ===
   bunx playwright install chromium firefox webkit
# Currently materialised at ~/.cache/ms-playwright/ (chromium symlinked to ~/bin/chromium).

# === Dotfiles bootstrap (after this Brewfile + apt + manuals) ===
   cd ~/dotfiles && stow .                 # per README; targets ~/.config (.stowrc)

# =============================================================================


echo "Done. Restart your shell."winget configure --file .\windows\configuration.dsc.yaml --accept-configuration-agreements
