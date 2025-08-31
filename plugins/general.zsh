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

bddc() {
    echo "$1" | base64 -Dd | zstd -d -o "$2"
}

bdsn() {
    echo "$1" | base64 -Dd | snzip -dc > "$2"
}

7zxe() {
    XE_PASSWORD=$(gen_pass -i "$1")
    7zz x -p"$XE_PASSWORD" "$1"
    unset XE_PASSWORD
}
