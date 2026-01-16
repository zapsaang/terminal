export LS_OPTIONS='--color=auto'

alias ll="ls $LS_OPTIONS -ahlF"
alias la="ls $LS_OPTIONS -A"
alias ls="ls $LS_OPTIONS"
alias l="ls $LS_OPTIONS -CF"

alias pip="pip3"
alias python="python3"

alias rm="rm -i"
alias cp="cp -i"
alias mv="mv -i"

alias sudo="sudo -i"

alias df="df -h"
alias du="du -h"

if (( $+commands[curlie] )); then
    alias curl="curlie"
fi
if (( $+commands[eza] )); then
    alias ll="eza -ahlgF --icons --group-directories-first --time-style=+%Y-%m-%d\ %H:%M:%S"
fi
if (( $+commands[bat] )); then
    alias cat="bat --paging=never"
fi
if (( $+commands[rg] )); then
    alias grep="rg"
fi
if (( $+functions[z] )); then
    alias cd="z"
fi

is_interactive_shell() {
    case "$-" in
        *i*) ;;        
        *) return 1 ;;
    esac
    [[ -t 0 ]] || return 1
    return 0
}

bddc() {
    echo "$1" | base64 -Dd | zstd -d -o "$2"
}

bdsn() {
    echo "$1" | base64 -Dd | snzip -dc > "$2"
}

mkcd() {
    mkdir -p "$1" && cd "$1"
}
