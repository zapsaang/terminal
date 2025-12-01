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

is_interactive_shell() {
    case "$-" in
        *i*) ;;        
        *) return 1 ;;
    esac
    [[ -t 0 ]] || return 1
    return 0
}

curl() {
    if (( $+commands[curlie] )); then
        alias curl="curlie"
    fi


}

if (( $+commands[curlie] )); then
    alias curl="curlie"
fi
if (( $+commands[eza] )); then
    alias ll="eza -ahlgF --icons --group-directories-first"
fi
if (( $+commands[bat] )); then
    alias cat="bat"
fi
if (( $+commands[rg] )); then
    alias grep="rg"
fi

bddc() {
    echo "$1" | base64 -Dd | zstd -d -o "$2"
}

bdsn() {
    echo "$1" | base64 -Dd | snzip -dc > "$2"
}

7zxe() {
    XE_PASSWORD=$(gen_pass -i "$1") && \
    7zz x -p"$XE_PASSWORD" -so "$1" | tar -xf -
    unset XE_PASSWORD
}

7zce() {
    CE_PASSWORD=$(gen_pass -i "$1") && \
    tar --ignore-failed-read -cf - $2 2>/dev/null | \
    7z a -mmt=off -t7z -mhe=on -p"$CE_PASSWORD" -si $1
    unset CE_PASSWORD
}

mkcd() {
    mkdir -p "$1" && cd "$1"
}
