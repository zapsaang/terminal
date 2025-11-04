for brew_path in "/opt/homebrew" "/home/linuxbrew/.linuxbrew"; do
    if [[ -s "$brew_path/bin/brew" ]] && (( ! $+commands[brew] )); then
        export HOMEBREW_PREFIX="$brew_path"
        export HOMEBREW_CELLAR="$brew_path/Cellar"
        export HOMEBREW_REPOSITORY="$brew_path"
        export PATH="$brew_path/bin:$brew_path/sbin${PATH+:$PATH}"
        export MANPATH="$brew_path/share/man${MANPATH+:$MANPATH}:"
        export INFOPATH="$brew_path/share/info:${INFOPATH:-}"
        break
    fi
done

alias bud="brew update && brew upgrade"
