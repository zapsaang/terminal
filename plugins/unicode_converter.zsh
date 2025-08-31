ucc() {
    # 检测Alfred环境
    local alfred_mode=false
    if [[ -n "$alfred_workflow_bundleid" ]] || [[ -n "$alfred_workflow_data" ]] || [[ -n "$alfred_version" ]]; then
        alfred_mode=true
    fi
    
    # 内部辅助函数 - 检测输入类型
    local _detect_input_type() {
        local input="$1"
        
        # 移除前导空白
        input="${input#"${input%%[![:space:]]*}"}"
        # 移除尾随空白  
        input="${input%"${input##*[![:space:]]}"}"
        
        # 优先检测连续的Unicode码点格式 U+XXXXU+XXXX...
        if [[ "$input" == U+* ]] && [[ "$input" == *U+* ]]; then
            # 检查是否只包含有效的Unicode码点字符
            local clean_input="${input//[U+0-9A-Fa-f]/}"
            if [[ -z "$clean_input" ]]; then
                # 进一步验证格式：每个U+后面应该跟4-6位十六进制数字
                local temp_input="$input"
                local valid=true
                while [[ "$temp_input" == U+* ]]; do
                    # 移除U+前缀
                    temp_input="${temp_input#U+}"
                    # 检查接下来的字符
                    if [[ ${#temp_input} -lt 4 ]]; then
                        valid=false
                        break
                    fi
                    # 提取十六进制部分（最多6位）
                    local hex_part=""
                    local i=0
                    while [[ $i -lt 6 ]] && [[ $i -lt ${#temp_input} ]]; do
                        local char="${temp_input:$i:1}"
                        if [[ "$char" =~ [0-9A-Fa-f] ]]; then
                            hex_part="${hex_part}${char}"
                            ((i++))
                        else
                            break
                        fi
                    done
                    
                    # 至少需要4位十六进制
                    if [[ ${#hex_part} -lt 4 ]]; then
                        valid=false
                        break
                    fi
                    
                    # 移除已处理的十六进制部分
                    temp_input="${temp_input:${#hex_part}}"
                done
                
                if [[ "$valid" == "true" ]] && [[ -z "$temp_input" ]]; then
                    echo "unicode"
                    return
                fi
            fi
        fi
        
        # 检测\uXXXX格式的Unicode编码
        if [[ "$input" == *\\u* ]]; then
            # 检查是否符合\uXXXX格式
            local clean_input="${input//[\\u0-9A-Fa-f]/}"
            if [[ -z "$clean_input" ]]; then
                # 进一步验证：每个\u后面应该跟4位十六进制数字
                local temp_input="$input"
                
                # 简化验证：检查是否匹配基本的\uXXXX模式
                if [[ "$temp_input" =~ \\u[0-9A-Fa-f]{4} ]]; then
                    # 计算\u出现的次数
                    local u_count=$(printf '%s' "$temp_input" | grep -o '\\u' | wc -l | tr -d ' ')
                    
                    # 移除所有\uXXXX模式，看看还剩什么
                    local without_unicode=$(printf '%s' "$temp_input" | sed 's/\\u[0-9A-Fa-f]\{4\}//g')
                    
                    # 如果移除所有\uXXXX后为空或只有少量其他字符，认为是有效的
                    # 允许一些非Unicode字符（如斜杠、数字等）
                    local threshold=$((${#temp_input} / 8))  # 提高阈值容忍度
                    if [[ ${#without_unicode} -le $threshold ]] || [[ ${#without_unicode} -le 10 ]]; then
                        echo "unicode_backslash"
                        return
                    fi
                fi
            fi
        fi
        
        # 检测单个Unicode码点格式 (U+XXXX 或 u+xxxx)
        if [[ "$input" == U+* ]] || [[ "$input" == u+* ]]; then
            # 检测单个Unicode码点
            local hex_part="${input#*+}"
            if [[ "$hex_part" =~ ^[0-9A-Fa-f]+$ ]] && [[ ${#hex_part} -ge 4 ]] && [[ ${#hex_part} -le 6 ]]; then
                echo "unicode"
                return
            fi
        fi
        
        # 检测URL编码格式
        if [[ "$input" == *%* ]]; then
            echo "url"
            return
        fi
        
        # 检测单独的十六进制Unicode码点（4-6位）
        if [[ ${#input} -ge 4 ]] && [[ ${#input} -le 6 ]]; then
            local cleaned_hex=$(echo "$input" | tr -d '0-9A-Fa-f')
            if [[ -z "$cleaned_hex" ]]; then
                echo "unicode"
                return
            fi
        fi
        
        # 检测UTF-8十六进制格式 (只包含十六进制字符，长度为偶数，且长度较长)
        if [[ ${#input} -gt 6 ]] && [[ $((${#input} % 2)) -eq 0 ]]; then
            local cleaned_hex=$(echo "$input" | tr -d '0-9A-Fa-f')
            if [[ -z "$cleaned_hex" ]]; then
                echo "hex"
                return
            fi
        fi
        
        # 检测Base64格式 (长度是4的倍数，只包含Base64字符，可能以=结尾)
        if [[ ${#input} -gt 4 ]] && [[ $((${#input} % 4)) -eq 0 ]]; then
            local cleaned_input=$(echo "$input" | tr -d 'A-Za-z0-9+/=')
            if [[ -z "$cleaned_input" ]]; then
                local hex_only=$(echo "$input" | tr -d '0-9A-Fa-f')
                if [[ -n "$hex_only" ]]; then
                    if echo "$input" | base64 -d >/dev/null 2>&1; then
                        echo "base64"
                        return
                    fi
                fi
            fi
        fi
        
        # 默认为普通文本
        echo "text"
    }
    
    # 内部辅助函数 - Unicode码点转字符
    local _unicode_to_char() {
        local input="$1"
        local result=""
        
        # 检查是否为连续的Unicode码点
        if [[ "$input" == U+* ]] && [[ "$input" == *U+* ]] && [[ "${input//[U+0-9A-Fa-f]/}" == "" ]]; then
            # 处理连续的Unicode码点 U+XXXXU+XXXX...
            local temp_input="$input"
            while [[ "$temp_input" == U+* ]]; do
                # 移除U+前缀
                temp_input="${temp_input#U+}"
                
                # 提取十六进制部分（最多6位）
                local hex_part=""
                local i=0
                while [[ $i -lt 6 ]] && [[ $i -lt ${#temp_input} ]]; do
                    local char="${temp_input:$i:1}"
                    if [[ "$char" =~ [0-9A-Fa-f] ]]; then
                        hex_part="${hex_part}${char}"
                        ((i++))
                    else
                        break
                    fi
                done
                
                # 转换这个码点为字符
                if [[ ${#hex_part} -ge 4 ]]; then
                    if command -v python3 >/dev/null 2>&1; then
                        local char=$(python3 -c "print(chr(0x$hex_part), end='')" 2>/dev/null)
                        result="${result}${char}"
                    else
                        local decimal=$((16#$hex_part))
                        result="${result}$(printf "\\u$(printf "%04x" $decimal)")"
                    fi
                fi
                
                # 移除已处理的十六进制部分
                temp_input="${temp_input:${#hex_part}}"
            done
        else
            # 处理单个Unicode码点
            input=$(echo "$input" | sed 's/^[Uu]+//g' | tr '[:lower:]' '[:upper:]')
            
            if command -v python3 >/dev/null 2>&1; then
                result=$(python3 -c "print(chr(0x$input), end='')" 2>/dev/null) || \
                result=$(printf "\\u$(printf "%04x" $((16#$input)))")
            else
                local decimal=$((16#$input))
                result=$(printf "\\u$(printf "%04x" $decimal)")
            fi
        fi
        
        echo "$result"
    }
    
    # 内部辅助函数 - \uXXXX格式转字符
    local _unicode_backslash_to_char() {
        local input="$1"
        local result=""
        
        if command -v python3 >/dev/null 2>&1; then
            # 使用Python的unicode_escape解码，通过stdin传递避免引号问题
            result=$(printf '%s' "$input" | python3 -c "
import sys
try:
    data = sys.stdin.read()
    # 解码unicode转义序列
    decoded = data.encode('utf-8').decode('unicode_escape')
    print(decoded, end='')
except Exception:
    sys.exit(1)
" 2>/dev/null)
            if [[ $? -eq 0 ]] && [[ -n "$result" ]]; then
                echo "$result"
                return 0
            fi
        fi
        
        # 手动解析\uXXXX格式（备用方案）
        local temp_input="$input"
        result=""
        
        while [[ "$temp_input" == *\\u* ]]; do
            # 找到\u的位置
            local before="${temp_input%%\\u*}"
            local after="${temp_input#*\\u}"
            
            # 提取4位十六进制数字
            local hex_code="${after:0:4}"
            local remaining="${after:4}"
            
            # 添加前面的部分
            result="${result}${before}"
            
            # 转换十六进制为字符
            if [[ ${#hex_code} -eq 4 ]] && [[ "$hex_code" =~ ^[0-9A-Fa-f]{4}$ ]]; then
                if command -v python3 >/dev/null 2>&1; then
                    local char=$(python3 -c "
try:
    print(chr(0x$hex_code), end='')
except:
    print('?', end='')
" 2>/dev/null)
                    result="${result}${char}"
                else
                    # 使用printf作为最后的备用方案
                    local decimal=$((16#$hex_code))
                    if [[ $decimal -lt 128 ]]; then
                        result="${result}$(printf "\\$(printf "%03o" $decimal)")"
                    else
                        result="${result}?"  # 无法处理的Unicode字符用?替代
                    fi
                fi
            else
                # 如果格式不正确，保持原样
                result="${result}\\u${hex_code}"
            fi
            
            temp_input="$remaining"
        done
        
        # 添加剩余部分
        result="${result}${temp_input}"
        echo "$result"
    }
    
    # 内部辅助函数 - UTF-8十六进制转字符串
    local _hex_to_str() {
        local input="$1"
        input=$(echo "$input" | tr -d ' \n\t' | tr '[:lower:]' '[:upper:]')
        
        if [[ ! "$input" =~ ^[0-9A-F]*$ ]] || (( ${#input} % 2 != 0 )); then
            return 1
        fi
        
        echo -n "$input" | xxd -r -p 2>/dev/null
    }
    
    # 内部辅助函数 - URL编码转字符串
    local _url_to_str() {
        local input="$1"
        python3 -c "import urllib.parse; print(urllib.parse.unquote('$input'))" 2>/dev/null || \
        echo -e "$(echo "$input" | sed 's/%/\\x/g')"
    }
    
    # 内部辅助函数 - Base64转字符串
    local _base64_to_str() {
        local input="$1"
        echo "$input" | base64 -d 2>/dev/null
    }
    
    # 内部辅助函数 - 生成Alfred JSON输出
    local _generate_alfred_json() {
        local input="$1"
        local input_type="$2"
        local result="$3"
        local conversion_info="$4"
        
        # 为Alfred生成多个可选择的项目
        local items=""
        
        if [[ "$input_type" == "text" ]]; then
            # 文本输入：提供多种编码选项
            local unicode_points=""
            for (( i=1; i<=${#input}; i++ )); do
                local char="${input:$((i-1)):1}"
                local codepoint=$(printf "%04X" "'$char")
                unicode_points="${unicode_points}U+${codepoint} "
            done
            unicode_points="${unicode_points% }"
            
            local hex_encoding=$(echo -n "$input" | xxd -p | tr -d '\n' | tr '[:lower:]' '[:upper:]')
            local url_encoding=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$input', safe=''))" 2>/dev/null || echo "N/A")
            local base64_encoding=$(echo -n "$input" | base64)
            
            items=$(cat << EOF
{
  "items": [
    {
      "uid": "unicode",
      "title": "Unicode码点",
      "subtitle": "$unicode_points",
      "arg": "$unicode_points",
      "text": {
        "copy": "$unicode_points",
        "largetype": "$unicode_points"
      },
      "icon": {
        "type": "default"
      }
    },
    {
      "uid": "hex",
      "title": "UTF-8十六进制",
      "subtitle": "$hex_encoding",
      "arg": "$hex_encoding",
      "text": {
        "copy": "$hex_encoding",
        "largetype": "$hex_encoding"
      },
      "icon": {
        "type": "default"
      }
    },
    {
      "uid": "url",
      "title": "URL编码",
      "subtitle": "$url_encoding",
      "arg": "$url_encoding",
      "text": {
        "copy": "$url_encoding",
        "largetype": "$url_encoding"
      },
      "icon": {
        "type": "default"
      }
    },
    {
      "uid": "base64",
      "title": "Base64编码",
      "subtitle": "$base64_encoding",
      "arg": "$base64_encoding",
      "text": {
        "copy": "$base64_encoding",
        "largetype": "$base64_encoding"
      },
      "icon": {
        "type": "default"
      }
    }
  ]
}
EOF
)
        else
            # 编码输入：显示转换结果
            items=$(cat << EOF
{
  "items": [
    {
      "uid": "result",
      "title": "$result",
      "subtitle": "$conversion_info",
      "arg": "$result",
      "text": {
        "copy": "$result",
        "largetype": "$result"
      },
      "icon": {
        "type": "default"
      }
    }
  ]
}
EOF
)
        fi
        
        echo "$items"
    }
    
    # 内部辅助函数 - 文本转各种编码格式
    local _text_to_encodings() {
        local input="$1"
        local format="$2"
        local json_output="$3"
        local quiet_mode="$4"
        
        case "$format" in
            "unicode")
                local result=""
                for (( i=1; i<=${#input}; i++ )); do
                    local char="${input:$((i-1)):1}"
                    local codepoint=$(printf "%04X" "'$char")
                    result="${result}U+${codepoint} "
                done
                echo "${result% }"
                ;;
            "hex")
                echo -n "$input" | xxd -p | tr -d '\n' | tr '[:lower:]' '[:upper:]'
                ;;
            "url")
                python3 -c "import urllib.parse; print(urllib.parse.quote('$input', safe=''))" 2>/dev/null || \
                echo -n "$input" | od -A n -t x1 | tr ' ' '%' | tr -d '\n' | sed 's/%$//;s/^%//'
                ;;
            "base64")
                echo -n "$input" | base64
                ;;
            *)
                # 生成所有格式
                local unicode_points=""
                for (( i=1; i<=${#input}; i++ )); do
                    local char="${input:$((i-1)):1}"
                    local codepoint=$(printf "%04X" "'$char")
                    unicode_points="${unicode_points}U+${codepoint} "
                done
                unicode_points="${unicode_points% }"
                
                local hex_encoding=$(echo -n "$input" | xxd -p | tr -d '\n' | tr '[:lower:]' '[:upper:]')
                local url_encoding=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$input', safe=''))" 2>/dev/null || echo "N/A")
                local base64_encoding=$(echo -n "$input" | base64)
                
                if [[ "$json_output" == "true" ]]; then
                    printf '{"input":"%s","type":"text","encodings":{"unicode":"%s","hex":"%s","url":"%s","base64":"%s"}}' \
                           "$input" "$unicode_points" "$hex_encoding" "$url_encoding" "$base64_encoding"
                elif [[ "$quiet_mode" == "true" ]] || [[ "$alfred_mode" == "true" ]]; then
                    # Alfred环境或静默模式：简洁输出
                    echo "Unicode: $unicode_points"
                    echo "Hex: $hex_encoding"
                    echo "URL: $url_encoding"
                    echo "Base64: $base64_encoding"
                else
                    echo "原始文本: $input"
                    echo "Unicode码点: $unicode_points"
                    echo "UTF-8十六进制: $hex_encoding"
                    echo "URL编码: $url_encoding"
                    echo "Base64编码: $base64_encoding"
                fi
                ;;
        esac
    }
    
    # 主函数逻辑开始
    local input_data=""
    local json_output=false
    local quiet_mode=false
    local show_analysis=false
    local output_format=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -j|--json)
                json_output=true
                shift
                ;;
            -q|--quiet)
                quiet_mode=true
                shift
                ;;
            -a|--analyze)
                show_analysis=true
                shift
                ;;
            -f|--format)
                if [[ -n "$2" ]]; then
                    output_format="$2"
                    shift 2
                else
                    if [[ "$alfred_mode" == "true" ]]; then
                        echo "Error: --format requires format parameter (unicode|hex|url|base64)" >&2
                    else
                        echo "错误: --format 需要指定格式参数 (unicode|hex|url|base64)" >&2
                    fi
                    return 1
                fi
                ;;
            -h|--help)
                cat << 'EOF'
unicode_convert - 智能Unicode字符转换函数

用法:
    unicode_convert [选项] <输入>

功能:
    自动检测输入类型并转换为人类可读的格式或编码格式

支持的输入格式:
    • 普通文本 → 显示各种编码格式
    • Unicode码点 (U+4E2D 或 4E2D) → 转换为字符
    • 连续Unicode码点 (U+4F60U+597D) → 转换为字符串
    • \\uXXXX转义格式 (\\u4F60\\u597D) → 转换为字符串
    • UTF-8十六进制 (E4B8ADE69687) → 转换为字符串
    • URL编码 (%E4%B8%AD%E6%96%87) → 转换为字符串
    • Base64编码 (SGVsbG8=) → 转换为字符串

选项:
    -j, --json      以JSON格式输出结果
    -q, --quiet     静默模式，只输出转换结果
    -a, --analyze   显示输入类型检测信息
    -f, --format    指定输出格式 (unicode|hex|url|base64)
    --alfred-simple 在Alfred环境中使用简洁模式输出
    -h, --help      显示此帮助信息

示例:
    unicode_convert "中文"
    unicode_convert "U+4E2D"
    unicode_convert "\\u4F60\\u597D"
    unicode_convert "E4B8ADE69687"
    unicode_convert -f hex "测试"
    unicode_convert -j "🌍"
    
Alfred Workflow 使用:
    默认情况下，在Alfred环境中会输出JSON格式的列表选项
    使用 --alfred-simple 参数可获得传统的简洁输出
EOF
                return 0
                ;;
            *)
                if [[ -z "$input_data" ]]; then
                    input_data="$1"
                    shift
                else
                    if [[ "$alfred_mode" == "true" ]]; then
                        echo "Error: Unknown option $1" >&2
                    else
                        echo "错误: 未知选项 $1" >&2
                    fi
                    return 1
                fi
                ;;
        esac
    done
    
    # 检查输入
    if [[ -z "$input_data" ]]; then
        # 尝试从标准输入读取
        if [[ ! -t 0 ]]; then
            input_data=$(cat)
        fi
        
        if [[ -z "$input_data" ]]; then
            if [[ "$alfred_mode" == "true" ]]; then
                echo "Error: No input data provided" >&2
            else
                echo "错误: 请提供输入数据" >&2
            fi
            return 1
        fi
    fi
    
    # 移除首尾空白
    input_data="${input_data#"${input_data%%[![:space:]]*}"}"   # 移除前导空白
    input_data="${input_data%"${input_data##*[![:space:]]}"}"   # 移除尾随空白
    
    if [[ -z "$input_data" ]]; then
        if [[ "$alfred_mode" == "true" ]]; then
            echo "Error: Input data is empty" >&2
        else
            echo "错误: 输入数据为空" >&2
        fi
        return 1
    fi
    
    # 检测输入类型
    local input_type=$(_detect_input_type "$input_data")
    
    # 显示分析信息
    if [[ "$show_analysis" == "true" ]] && [[ "$quiet_mode" != "true" ]]; then
        echo "检测到输入类型: $input_type" >&2
    fi
    
    local result=""
    local conversion_info=""
    
    # 根据类型执行转换
    case "$input_type" in
        "unicode")
            result=$(_unicode_to_char "$input_data")
            conversion_info="Unicode码点 → 字符"
            ;;
        "unicode_backslash")
            result=$(_unicode_backslash_to_char "$input_data")
            conversion_info="\\uXXXX格式 → 字符串"
            ;;
        "hex")
            result=$(_hex_to_str "$input_data")
            if [[ $? -ne 0 ]]; then
                if [[ "$alfred_mode" == "true" ]]; then
                    echo "Error: Invalid hex encoding: $input_data" >&2
                else
                    echo "错误: 无效的十六进制编码: $input_data" >&2
                fi
                return 1
            fi
            conversion_info="UTF-8十六进制 → 字符串"
            ;;
        "url")
            result=$(_url_to_str "$input_data")
            conversion_info="URL编码 → 字符串"
            ;;
        "base64")
            result=$(_base64_to_str "$input_data")
            if [[ $? -ne 0 ]]; then
                if [[ "$alfred_mode" == "true" ]]; then
                    echo "Error: Invalid Base64 encoding: $input_data" >&2
                else
                    echo "错误: 无效的Base64编码: $input_data" >&2
                fi
                return 1
            fi
            conversion_info="Base64编码 → 字符串"
            ;;
        "text")
            if [[ -n "$output_format" ]]; then
                result=$(_text_to_encodings "$input_data" "$output_format")
                conversion_info="文本 → ${output_format}编码"
            elif [[ "$alfred_mode" == "true" ]]; then
                # Alfred模式：不调用_text_to_encodings，而是由后面的输出逻辑处理
                result="$input_data"
                conversion_info="文本 → 多种编码格式"
            else
                _text_to_encodings "$input_data" "" "$json_output" "$quiet_mode"
                return 0
            fi
            ;;
    esac
    
    # 输出结果
    if [[ "$alfred_mode" == "true" ]] && [[ "$alfred_simple" == "true" ]]; then
        # Alfred简洁模式：向后兼容
        if [[ "$input_type" == "text" ]]; then
            _text_to_encodings "$input_data" "" false true
        else
            echo "$result"
        fi
    elif [[ "$alfred_mode" == "true" ]] && [[ "$json_output" != "true" ]]; then
        # Alfred环境：使用专门的JSON格式
        _generate_alfred_json "$input_data" "$input_type" "$result" "$conversion_info"
    elif [[ "$json_output" == "true" ]]; then
        # 标准JSON输出
        printf '{"input":"%s","type":"%s","result":"%s","conversion":"%s"}' \
               "$input_data" "$input_type" "$result" "$conversion_info"
    elif [[ "$quiet_mode" == "true" ]]; then
        echo "$result"
    else
        echo "输入: $input_data"
        echo "类型: $input_type"
        echo "转换: $conversion_info"
        echo "结果: $result"
    fi
    
    return 0
}
