# Clipboard bridge for Claude Code image paste (Alt-V) over SSH.
#
# Remote half: headless SSH sessions get a tiny Xvfb display so xclip has a
# clipboard for Claude Code to read. Local half: `push-clip <host>` sends the
# Windows clipboard image into that remote clipboard.
#
# Flow: screenshot locally → push-clip <host> → Alt-V in remote Claude Code.

# Remote half — only when SSH'd in with no real display available.
if [[ -n $SSH_CONNECTION && -z $DISPLAY ]] && command -v Xvfb &>/dev/null; then
  pgrep -x Xvfb >/dev/null || Xvfb :99 -screen 0 1x1x8 &>/dev/null &!
  export DISPLAY=:99
fi

# Local half — WSL only. ponytail: add pngpaste/xclip branches if these
# dotfiles ever land on a macOS/Linux desktop that needs it.
if command -v powershell.exe &>/dev/null; then
  push-clip() {
    local host=${1:?usage: push-clip <ssh-host>}
    local win='C:\Users\Public\push-clip.png' wsl=/mnt/c/Users/Public/push-clip.png
    powershell.exe -NoProfile -Command "
      \$i = Get-Clipboard -Format Image
      if (-not \$i) { exit 1 }
      \$i.Save('$win', [System.Drawing.Imaging.ImageFormat]::Png)" \
      || { print -u2 'push-clip: no image on the Windows clipboard'; return 1 }
    # setsid keeps the forked xclip (which serves the selection) alive after ssh exits
    ssh "$host" 'DISPLAY=:99 setsid nohup xclip -selection clipboard -t image/png -i >/dev/null 2>&1' <"$wsl" \
      && print "push-clip: image ready on $host — press Alt-V in Claude Code"
    command rm -f "$wsl"
  }
fi
