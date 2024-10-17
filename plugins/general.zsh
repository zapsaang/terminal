export LS_OPTINS='--color=auto'

alias ll='ls $LS_OPTINS -ahlF'
alias la='ls $LS_OPTINS -A'
alias ls='ls $LS_OPTINS'
alias l='ls $LS_OPTINS -CF'

alias pip='pip3'
alias python='python3'

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

alias sudo='sudo -i'

alias df='df -h'
alias du='du -h'

function bddc() {
    echo "$1" | base64 -Dd | zstd -d -o "$2.decompressed"
}
