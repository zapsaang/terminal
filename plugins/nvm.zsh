export NVM_DIR="$HOME/.nvm"

function nvmup() {
  if [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
    source "/opt/homebrew/opt/nvm/nvm.sh" # This loads nvm
  else
    echo "NVM script not found at /opt/homebrew/opt/nvm/nvm.sh"
    return 1
  fi

  if [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ]; then
    source "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" # This loads nvm bash_completion
  fi

  if [[ -n "$1" ]]; then
    nvm use "$1"
  else
    nvm use --lts || (nvm install --lts && nvm use --lts)
  fi
}

if functions command_not_found_handler > /dev/null 2>&1 && ! alias _original_command_not_found_handler_covered_by_nvmup > /dev/null 2>&1; then
  alias _original_command_not_found_handler_covered_by_nvmup=command_not_found_handler
fi

function command_not_found_handler() {
  local cmd=$1

  if [[ "$cmd" == "npm" || "$cmd" == "node" || "$cmd" == "nvm" ]]; then
    echo "$cmd not found, automatically loading nvm..." >&2
    nvmup

    if command -v "$cmd" >/dev/null 2>&1; then
      echo "Retrying '$cmd'..." >&2
      "$cmd" "${@:2}" 
      return $?
    else
      echo "Failed to load '$cmd' via nvm." >&2
      return 127
    fi
  fi

  if command -v _original_command_not_found_handler_covered_by_nvmup >/dev/null 2>&1; then
    _original_command_not_found_handler_covered_by_nvmup "$@"
    return $?
  fi

  echo "zsh: command not found: $cmd" >&2
  return 127
}
