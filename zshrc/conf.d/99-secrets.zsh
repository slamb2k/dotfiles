# Source secret credential files if they exist.
# These files live in ~/.config/secrets/ (outside git) and contain API keys,
# tokens, and other credentials. This file just wires them up.
for _secret in openrouter gemini pocketsmith azure_devops openrouter_api_key; do
  [[ -r "$HOME/.config/secrets/${_secret}.zsh" ]] && source "$HOME/.config/secrets/${_secret}.zsh"
done
unset _secret
