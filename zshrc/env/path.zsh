# PATH and tool locations for every zsh, interactive or not. Sourced from ~/.zshenv, so scripts and
# non-interactive shells (Claude Code, ssh commands) get it too, and again from conf.d/00-env.zsh.
# It runs for every zsh, so keep it fast: no subprocesses. Later prepends win (rightmost = highest).

# Homebrew: static equivalent of `brew shellenv` (running brew costs ~20ms per shell)
if [[ -d /home/linuxbrew/.linuxbrew ]]; then
  export HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
  export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar" HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX/Homebrew"
  fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
  path=("$HOMEBREW_PREFIX/bin" "$HOMEBREW_PREFIX/sbin" $path)
  [[ ":$INFOPATH:" == *":$HOMEBREW_PREFIX/share/info:"* ]] || export INFOPATH="$HOMEBREW_PREFIX/share/info:${INFOPATH:-}"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Language/runtime/tool directories
[[ -d "$HOME/.cargo/bin" ]]               && path=("$HOME/.cargo/bin" $path)
[[ -d "$HOME/.local/share/mise/shims" ]]  && path=("$HOME/.local/share/mise/shims" $path)
[[ -d "$HOME/.local/bin" ]]               && path=("$HOME/.local/bin" $path)
[[ -d "$HOME/.bun/bin" ]]                 && path=("$HOME/.bun/bin" $path) && export BUN_INSTALL="$HOME/.bun"
[[ -d "$HOME/bin" ]]                      && path=("$HOME/bin" $path)

# .NET / Power Platform CLI
export DOTNET_ROOT="$HOME/.dotnet"
[[ -d $DOTNET_ROOT ]]                      && path=("$DOTNET_ROOT" $path)
[[ -d "$HOME/.local/pac/tools" ]]         && path=("$HOME/.local/pac/tools" $path)

# opencode
[[ -d "$HOME/.opencode/bin" ]]            && path=("$HOME/.opencode/bin" $path)

# Go (provided by Homebrew; do not force GOROOT to old /usr/local/go)
export GOPATH="$HOME/go"
[[ -d "$GOPATH/bin" ]]                    && path=($path "$GOPATH/bin")

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
[[ -d $PNPM_HOME ]]                       && path=("$PNPM_HOME" $path)

# nvm's default node without loading nvm.sh (~1s). "lts/*" means the newest LTS alias.
# Interactive shells still load nvm.sh in conf.d/00-env.zsh for `nvm use`.
() {
  local nvm="$HOME/.nvm" v f
  local -a vs dirs
  [[ -r "$nvm/alias/default" ]] || return
  v=$(<"$nvm/alias/default")
  if [[ $v == 'lts/*' ]]; then
    for f in "$nvm"/alias/lts/*(N); vs+=("$(<$f)")
    v=${${(On)vs}[1]}
  elif [[ -r "$nvm/alias/$v" ]]; then
    v=$(<"$nvm/alias/$v")
  fi
  dirs=("$nvm"/versions/node/v${v#v}*(N/nOn))
  (( $#dirs )) && path=("$dirs[1]/bin" $path)
}

typeset -U path PATH fpath
