# Auto-attach to tmux on SSH login (VM only — avoids nested sessions locally)
# Disabled: do not force every SSH login into tmux.
# To re-enable, uncomment this block.
# if [[ -n "$SSH_CONNECTION" && -z "$TMUX" && $- == *i* ]]; then
#   tmux attach-session -t main 2>/dev/null || tmux new-session -s main
# fi
