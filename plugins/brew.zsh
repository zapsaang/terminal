for brew_path in "/opt/homebrew" "/home/linuxbrew/.linuxbrew"; do
    brew_bin="$brew_path/bin"
    brew_sbin="$brew_path/sbin"
    if [[ -s "$brew_path/bin/brew" ]] && (( ! ${path[(I)(#q)$brew_sbin]} )); then
        export HOMEBREW_PREFIX="$brew_path"
        export HOMEBREW_CELLAR="$brew_path/Cellar"
        export HOMEBREW_REPOSITORY="$brew_path"
        export MANPATH="$brew_path/share/man${MANPATH+:$MANPATH}:"
        export INFOPATH="$brew_path/share/info:${INFOPATH:-}"

        path=("$brew_bin" "$brew_sbin" $path)
        typeset -U path
        break
    fi
done

alias bud="brew update && brew upgrade"
