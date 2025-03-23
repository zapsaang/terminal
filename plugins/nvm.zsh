function nvmup() {
  export NVM_DIR="$HOME/.nvm"
    [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
    [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
  if [[ -n "$1" ]]; then
    nvm use "$1"
  else
    nvm use --lts || (nvm install --lts && nvm use --lts)
  fi
}

if functions command_not_found_handler > /dev/null; then
  alias _original_command_not_found_handler_covered_by_nvmup=command_not_found_handler
fi

function command_not_found_handler() {
  if [[ "$1" == "npm" ]]; then
    echo "npm not found, try to automatically load nvm..."
    nvmup
    echo "retry npm..."
    exec npm "${@:2}"
    return 0
  fi

  if command -v _original_command_not_found_handler_covered_by_nvmup >/dev/null; then
    _original_command_not_found_handler_covered_by_nvmup "$@"
    return $?
  fi

  echo "zsh: command not found: $1"
  return 127
}
