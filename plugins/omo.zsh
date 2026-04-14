omo_switch() {
    local suffix="$1"
    local base_dir="$HOME/.config/opencode"
    local config_path="${base_dir}/oh-my-openagent.json"
    
    if [ -z "$suffix" ]; then
        if command -v fzf >/dev/null 2>&1; then
            suffix=$(ls "${base_dir}"/oh-my-openagent.json.bak.* 2>/dev/null | \
                     sed "s|${base_dir}/oh-my-openagent.json.bak.||" | fzf --height 40% --reverse --prompt="选择配置后缀: ")
        else
            echo "提示: 未安装 fzf，请手动输入参数或安装 fzf。"
            return 1
        fi
        [ -z "$suffix" ] && return 0
    fi

    local target_file="${base_dir}/oh-my-openagent.json.bak.${suffix}"

    if [ ! -f "$target_file" ]; then
        echo "错误: 找不到备份文件 $target_file"
        return 1
    fi

    if [ -L "$config_path" ]; then
        rm -f "$config_path"
    elif [ -f "$config_path" ]; then
        local timestamp=$(date +%Y%m%d%H%M%S)
        echo "警告: 检测到真实文件，已备份为 .json.bak.orig.${timestamp}"
        mv "$config_path" "${config_path}.bak.orig.${timestamp}"
    fi

    ln -s "$target_file" "$config_path"
    echo "成功: 已将 $config_path 指向 [ $suffix ]"
}

_omo_switch_completion() {
    local base_dir="$HOME/.config/opencode"
    local -a files
    files=($(ls ${base_dir}/oh-my-openagent.json.bak.* 2>/dev/null | sed "s|${base_dir}/oh-my-openagent.json.bak.||"))
    _describe 'opencode_backups' files
}
compdef _omo_switch_completion omo_switch
