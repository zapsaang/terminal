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
        nvim "+call cursor($line, $col)" "$file" </dev/tty >/dev/tty 2>&1
    fi
}

function _zt-telescope_widget() {
    zle -I
    zt-telescope
    zle reset-prompt
    zle redisplay
}
zle -N _zt-telescope_widget
bindkey '^Xf' _zt-telescope_widget

function zt-sessionizer() {
    local PROJECT_DIR=$(
        (
            fd . ~/Code --min-depth 4 --max-depth 4 --type d &
            fd . ~/Projects --min-depth 3 --max-depth 3 --type d &
            fd . ~/.config --min-depth 1 --max-depth 1 --type d &
            
            wait
        ) 2>/dev/null | fzf --height 60% --layout=reverse --preview 'eza -1aTF --color=always --icons --group-directories-first {1}' --preview-window 'right,60%,border-left,+{2}+3/3,~3'
    )

    if [[ -z "$PROJECT_DIR" ]]; then
        return 0
    fi

    local PROJECT_NAME=$(basename "$PROJECT_DIR" | tr '.' '_')
    local ABS_DIR=$(builtin cd "$PROJECT_DIR" 2>/dev/null && pwd)

    if [[ -n "$ZELLIJ" ]]; then
        zellij action new-tab --cwd "$ABS_DIR" --name "$PROJECT_NAME"
    elif [[ -n "$TMUX" ]]; then
        if ! tmux has-session -t "$PROJECT_NAME" 2> /dev/null; then
            tmux new-session -d -s "$PROJECT_NAME" -c "$ABS_DIR"
        fi
        tmux switch-client -t "$PROJECT_NAME"
    else
        zellij attach -c "$PROJECT_NAME" options --default-cwd "$ABS_DIR" </dev/tty >/dev/tty 2>&1
    fi
}

function _zt-sessionizer_widget() {
    zle -I
    zt-sessionizer
    zle reset-prompt
    zle redisplay
}

zle -N _zt-sessionizer_widget
bindkey '^Xe' _zt-sessionizer_widget
