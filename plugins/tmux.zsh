
function zt-telescope() {
    local RG_PREFIX="rg --column --line-number --no-heading --color=always --smart-case"
    
    local selection=$(
        FZF_DEFAULT_COMMAND="$RG_PREFIX ''" \
        fzf --bind "change:reload:$RG_PREFIX {q} || true" \
            --ansi --disabled --query "" \
            --delimiter ':' \
            --height=100% --layout=reverse \
            --preview 'bat --style=numbers --color=always --highlight-line {2} {1}' \
            --preview-window 'right,50%,border-left,+{2}+3/3,~3'
    )

    if [[ -z "$selection" ]]; then
        return 0
    fi

    local file line col _rest
    IFS=: read -r file line col _rest <<< "$selection"

    if [[ -n "$ZELLIJ" ]]; then
        zellij action new-pane -c nvim "+call cursor($line, $col)" "$file"
    elif [[ -n "$TMUX" ]]; then
        tmux split-window -h "nvim '+call cursor($line, $col)' '$file'"
    else
        nvim "+call cursor($line, $col)" "$file"
    fi
}

function _zt-telescope_widget() {
    zt-telescope
    
    zle reset-prompt
    zle redisplay
}
zle -N _zt-telescope_widget
bindkey '^f' _zt-telescope_widget

function zt-sessionizer() {
    local PROJECT_DIR=$(fd . ~/Project ~/Code ~/.config \
        --min-depth 1 --max-depth 2 --type d 2>/dev/null \
        | fzf --height 40% --reverse --border=rounded --prompt="🚀 Project > ")

    if [[ -z "$PROJECT_DIR" ]]; then
        return 0
    fi

    local PROJECT_NAME=$(basename "$PROJECT_DIR" | tr '.' '_')

    if [[ -n "$ZELLIJ" ]]; then
        zellij action new-tab -l default -c "$PROJECT_DIR" -n "$PROJECT_NAME"
        
    elif [[ -n "$TMUX" ]]; then
        if ! tmux has-session -t "$PROJECT_NAME" 2> /dev/null; then
            tmux new-session -d -s "$PROJECT_NAME" -c "$PROJECT_DIR"
        fi
        tmux switch-client -t "$PROJECT_NAME"
        
    else
        cd "$PROJECT_DIR" || return 1
        zellij attach -c "$PROJECT_NAME"
    fi
}

function _zt-sessionizer_widget() {
    zt-sessionizer
    zle reset-prompt
    zle redisplay
}

zle -N _zt-sessionizer_widget
bindkey '^e' _zt-sessionizer_widget
