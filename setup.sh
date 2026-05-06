#!/usr/bin/env bash
# ~/dotfiles/setup.sh
#
# Restore the WSL/Linux side of the dev box.
#
# Usage:
#   ./setup.sh              # apply everything (real run)
#   ./setup.sh --dry-run    # show what would change, make no modifications
#   ./setup.sh -h           # this help text
#
# Idempotent. Safe to re-run.
set -euo pipefail

# -----------------------------------------------------------------------------
# Args
# -----------------------------------------------------------------------------
DRY_RUN=
for arg in "$@"; do
  case $arg in
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help)    sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

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
# bun globals
# -----------------------------------------------------------------------------
section 'bun globals'
BUN_GLOBALS=(
  @google/clasp @openai/codex @steipete/bird clawdhub happy-dom markdown-pdf
  marked mcporter md-to-pdf pdfkit playwright puppeteer-core
)
if ! command -v bun &>/dev/null; then
  note '(bun not installed yet — install via Brewfile or curl-bash first)'
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
GH_EXTENSIONS=(dlvhdr/gh-dash github/gh-copilot)
if ! command -v gh &>/dev/null; then
  note '(gh not installed yet — install via Brewfile first)'
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
UV_TOOLS=(graphifyy nano-pdf)
if ! command -v uv &>/dev/null; then
  note '(uv not installed yet — install via Brewfile first)'
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
