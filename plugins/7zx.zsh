7zx() {
    local action=""
    local source=""
    local target=""
    local password=""
    local extra_7z_args=""
    local extra_tar_args=""
    local verbose=false
    local use_tar=true
    local gen_pass=false
    
    # 提升作用域的命令变量，避免重复检测
    local sevenz_cmd=""
    local tar_cmd=""
    
    # ===== 统一错误处理和陷阱管理 =====
    
    # 全局错误状态跟踪
    local -a cleanup_files=()
    local -a cleanup_functions=()
    local error_context=""
    local operation_start_time=""

    # 统一陷阱管理器
    _setup_global_trap() {
        trap '_global_cleanup_handler $? EXIT' EXIT
        trap '_global_cleanup_handler $? INT' INT
        trap '_global_cleanup_handler $? TERM' TERM
        trap '_global_cleanup_handler $? HUP' HUP
        operation_start_time=$(date +%s)
    }
    
    # 全局清理处理器
    _global_cleanup_handler() {
        local exit_code=${1:-0}
        local signal=${2:-"EXIT"}
        
        # 记录操作持续时间
        if [[ -n "$operation_start_time" ]]; then
            local end_time=$(date +%s)
            local duration=$((end_time - operation_start_time))
            [[ "$verbose" == true ]] && _log_info "Operation duration: ${duration}s"
        fi
        
        # 执行清理函数
        for cleanup_func in "${cleanup_functions[@]}"; do
            if [[ -n "$cleanup_func" ]]; then
                _log_info "Executing cleanup: $cleanup_func"
                eval "$cleanup_func" 2>/dev/null || _log_warning "Cleanup function failed: $cleanup_func"
            fi
        done
        
        # 清理临时文件
        for temp_file in "${cleanup_files[@]}"; do
            if [[ -n "$temp_file" && -f "$temp_file" ]]; then
                _secure_file_cleanup "$temp_file"
            fi
        done
        
        # 重置陷阱
        trap - EXIT INT TERM HUP
        
        # 如果是信号中断，显示相应信息
        if [[ "$signal" != "EXIT" ]]; then
            _log_error "Operation interrupted by signal: $signal"
            if [[ -n "$error_context" ]]; then
                _log_error "Context: $error_context"
            fi
            exit 130  # 130 = 128 + 2 (SIGINT)
        fi
        
        # 正常退出时显示上下文信息（如果有错误）
        if [[ $exit_code -ne 0 && -n "$error_context" ]]; then
            _log_error "Operation failed in context: $error_context"
        fi
    }
    
    # 注册清理文件
    _register_cleanup_file() {
        local file="$1"
        cleanup_files+=("$file")
    }
    
    # 注册清理函数
    _register_cleanup_function() {
        local func="$1"
        cleanup_functions+=("$func")
    }
    
    # 设置错误上下文
    _set_error_context() {
        error_context="$1"
        _log_info "Entering context: $error_context"
    }
    
    # 清除错误上下文
    _clear_error_context() {
        [[ -n "$error_context" ]] && _log_info "Exiting context: $error_context"
        error_context=""
    }
    
    # 安全文件清理（包含敏感数据覆盖）
    _secure_file_cleanup() {
        local file="$1"
        if [[ -f "$file" ]]; then
            # 检查文件是否可能包含敏感数据（密码文件）
            if [[ "$file" == *"pass"* ]] || [[ "$file" == *"secret"* ]]; then
                # 用随机数据覆盖文件内容
                dd if=/dev/urandom of="$file" bs=1024 count=1 2>/dev/null || true
                _log_info "Securely overwritten sensitive file: $file"
            fi
            rm -f "$file" 2>/dev/null
            _log_info "Cleaned up file: $file"
        fi
    }
    
    # 增强的错误处理函数
    _handle_critical_error() {
        local exit_code=${1:-1}
        local error_msg="$2"
        local recovery_suggestion="${3:-}"
        local error_details="${4:-}"
        
        _log_error "CRITICAL ERROR: $error_msg"
        [[ -n "$error_details" ]] && _log_error "Details: $error_details"
        [[ -n "$recovery_suggestion" ]] && _log_error "Suggestion: $recovery_suggestion"
        [[ -n "$error_context" ]] && _log_error "Context: $error_context"
        
        # 记录系统状态用于调试（修复兼容性）
        if [[ "$verbose" == true ]]; then
            local free_space="unknown"
            local memory_info="unknown"
            
            # 检测磁盘空间（兼容macOS和Linux）
            if command -v df >/dev/null 2>&1; then
                free_space=$(df -h . 2>/dev/null | tail -n 1 | awk '{print $4}' 2>/dev/null || echo 'unknown')
            fi
            
            # 检测内存信息（兼容不同系统）
            if command -v free >/dev/null 2>&1; then
                memory_info=$(free -h 2>/dev/null | grep '^Mem:' | awk '{print $7}' 2>/dev/null || echo 'unknown')
            elif [[ -r /proc/meminfo ]]; then
                memory_info=$(grep '^MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2 " " $3}' || echo 'unknown')
            fi
            
            _log_error "System Info - Free space: $free_space"
            _log_error "System Info - Memory: $memory_info"
        fi
        
        return $exit_code
    }
    
    # 可恢复错误处理
    _handle_recoverable_error() {
        local exit_code=${1:-1}
        local error_msg="$2"
        local recovery_action="${3:-}"
        local max_retries="${4:-0}"
        
        _log_warning "Recoverable error: $error_msg"
        
        if [[ $max_retries -gt 0 && -n "$recovery_action" ]]; then
            _log_info "Attempting recovery: $recovery_action"
            for ((i=1; i<=max_retries; i++)); do
                _log_info "Recovery attempt $i/$max_retries"
                if eval "$recovery_action"; then
                    _log_ok "Recovery successful on attempt $i"
                    return 0
                fi
                [[ $i -lt $max_retries ]] && sleep $((i * 2))  # 递增延迟
            done
            _log_error "Recovery failed after $max_retries attempts"
        fi
        
        return $exit_code
    }

    # ===== 内部函数定义 =====
    
    # 检测7z命令（设置全局变量）
    _detect_7z_command() {
        _set_error_context "7z command detection"
        
        if command -v 7zz >/dev/null 2>&1; then
            sevenz_cmd="7zz"
            _log_info "Found 7zz command: $(which 7zz)"
        elif command -v 7z >/dev/null 2>&1; then
            sevenz_cmd="7z"
            _log_info "Found 7z command: $(which 7z)"
        else
            _handle_critical_error 1 "No 7z command found" \
                "Install 7-Zip: brew install p7zip (macOS) or apt-get install p7zip-full (Ubuntu)" \
                "Required for archive operations"
            return 1
        fi
        
        # 验证命令版本
        local version_output
        if version_output=$("$sevenz_cmd" --help 2>&1 | head -1); then
            _log_info "7z version: $version_output"
        else
            _handle_critical_error 1 "7z command is not working properly" \
                "Reinstall 7-Zip or check PATH" \
                "Command exists but returns error: $version_output"
            return 1
        fi
        
        _clear_error_context
        return 0
    }

    # 检测tar命令（设置全局变量）
    _detect_tar_command() {
        _set_error_context "tar command detection"
        
        if command -v gtar >/dev/null 2>&1; then
            tar_cmd="gtar"
            _log_info "Found GNU tar: $(which gtar)"
        elif command -v tar >/dev/null 2>&1; then
            tar_cmd="tar"
            _log_info "Found tar: $(which tar)"
            
            # 检查是否为GNU tar
            if tar --version 2>/dev/null | grep -q "GNU tar"; then
                _log_info "Detected GNU tar features"
            else
                _log_warning "Non-GNU tar detected, some features may be limited"
            fi
        else
            _handle_critical_error 1 "No tar command found" \
                "Install tar: available in most UNIX systems" \
                "Required for tar-based compression"
            return 1
        fi
        
        _clear_error_context
        return 0
    }
    
    # 通用参数分割函数（避免重复的数组分割逻辑）
    _split_args() {
        local args_string="$1"
        local -a result_array
        if [[ -n "$args_string" ]]; then
            local IFS=' '
            result_array=(${=args_string})  # zsh word splitting
        fi
        printf '%s\n' "${result_array[@]}"
    }
    
    # 日志输出函数 - 增强版本，修复日期命令兼容性
    _log_info() {
        if [[ "$verbose" == true ]]; then
            echo "[INFO $(date '+%H:%M:%S' 2>/dev/null || echo '')] $*" >&2
        fi
    }
    
    _log_error() {
        echo "[ERROR $(date '+%H:%M:%S' 2>/dev/null || echo '')] $*" >&2
    }
    
    _log_ok() {
        echo "[OK $(date '+%H:%M:%S' 2>/dev/null || echo '')] $*"
    }
    
    _log_warning() {
        if [[ "$verbose" == true ]]; then
            echo "[WARNING $(date '+%H:%M:%S' 2>/dev/null || echo '')] $*" >&2
        fi
    }
    
    _log_debug() {
        if [[ "$verbose" == true ]]; then
            echo "[DEBUG $(date '+%H:%M:%S' 2>/dev/null || echo '')] $*" >&2
        fi
    }

    # 统一错误处理包装函数 - 已被新的错误处理机制替代
    _handle_error() {
        local exit_code=$1
        local error_msg="$2"
        local cleanup_func="${3:-}"
        
        if [[ $exit_code -ne 0 ]]; then
            _log_error "$error_msg"
            [[ -n "$cleanup_func" ]] && eval "$cleanup_func"
            return $exit_code
        fi
        return 0
    }

    # 临时文件管理 - 集成到统一陷阱系统
    _cleanup_temp_files() {
        local temp_file="$1"
        if [[ -n "$temp_file" && -f "$temp_file" ]]; then
            _secure_file_cleanup "$temp_file"
        fi
    }

    # 设置临时文件清理陷阱 - 已被统一陷阱管理替代
    _setup_cleanup_trap() {
        local temp_file="$1"
        _register_cleanup_file "$temp_file"
    }
    
    # 验证文件/目录存在性和权限 - 增强错误信息
    _validate_source_file() {
        local file="$1"
        _set_error_context "source file validation: $file"
        
        if [[ ! -f "$file" ]]; then
            if [[ ! -e "$file" ]]; then
                _handle_critical_error 1 "Archive file does not exist: $file" \
                    "Check file path and spelling" \
                    "File not found in filesystem"
            else
                _handle_critical_error 1 "Path exists but is not a regular file: $file" \
                    "Ensure you specify a file, not a directory" \
                    "Path type: $(file "$file" 2>/dev/null || echo 'unknown')"
            fi
            return 1
        fi
        
        if [[ ! -r "$file" ]]; then
            _handle_critical_error 1 "Archive file is not readable: $file" \
                "Check file permissions: chmod +r '$file'" \
                "Current permissions: $(ls -la "$file" 2>/dev/null | awk '{print $1}' || echo 'unknown')"
            return 1
        fi
        
        if [[ ! -s "$file" ]]; then
            _handle_critical_error 1 "Archive file is empty: $file" \
                "File exists but has zero size - may be corrupted" \
                "File size: $(ls -la "$file" 2>/dev/null | awk '{print $5}' || echo 'unknown') bytes"
            return 1
        fi
        
        # 额外检查：文件大小合理性
        local file_size
        file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        if [[ $file_size -gt 0 ]]; then
            _log_info "Archive file size: $(numfmt --to=iec $file_size 2>/dev/null || echo "$file_size bytes")"
        fi
        
        _clear_error_context
        return 0
    }
    
    _validate_source_path() {
        local path="$1"
        _set_error_context "source path validation: $path"
        
        # 支持多个文件路径（空格分隔）
        local -a paths
        paths=(${=path})  # zsh word splitting
        
        local missing_paths=()
        for p in "${paths[@]}"; do
            if [[ ! -e "$p" ]]; then
                missing_paths+=("$p")
            else
                _log_debug "Source exists: $p ($(file "$p" 2>/dev/null | cut -d: -f2- | sed 's/^[[:space:]]*//' || echo 'unknown type'))"
            fi
        done
        
        if [[ ${#missing_paths[@]} -gt 0 ]]; then
            _handle_critical_error 1 "Source paths do not exist: ${missing_paths[*]}" \
                "Check paths and spelling" \
                "Working directory: $(pwd), Missing: ${#missing_paths[@]}/${#paths[@]} paths"
            return 1
        fi
        
        _clear_error_context
        return 0
    }
    
    _validate_target_directory() {
        local target="$1"
        _set_error_context "target directory validation: $target"
        
        local target_dir
        target_dir=$(dirname "$target")
        
        if [[ ! -d "$target_dir" ]]; then
            _handle_critical_error 1 "Target directory does not exist: $target_dir" \
                "Create directory: mkdir -p '$target_dir'" \
                "Parent directory missing for target: $target"
            return 1
        fi
        
        if [[ ! -w "$target_dir" ]]; then
            _handle_critical_error 1 "Target directory is not writable: $target_dir" \
                "Fix permissions: chmod +w '$target_dir'" \
                "Current permissions: $(ls -lad "$target_dir" 2>/dev/null | awk '{print $1}' || echo 'unknown')"
            return 1
        fi
        
        # 检查磁盘空间
        local available_space
        available_space=$(df "$target_dir" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
        if [[ $available_space -lt 1048576 ]]; then  # 少于1GB
            _log_warning "Low disk space in target directory: $(numfmt --to=iec $((available_space * 1024)) 2>/dev/null || echo "${available_space}KB")"
        fi
        
        _clear_error_context
        return 0
    }
    
    _validate_extract_target() {
        local target="$1"
        _set_error_context "extract target validation: $target"
        
        # 检查目标路径是否包含危险的路径遍历模式
        if [[ "$target" == *../* ]] || [[ "$target" == */../* ]] || [[ "$target" == ../* ]]; then
            _handle_critical_error 1 "Target path contains path traversal patterns: $target" \
                "Use absolute paths or remove '..' components" \
                "Security risk: potential directory traversal attack"
            return 1
        fi
        
        # 验证目标目录权限
        if [[ ! -d "$target" ]]; then
            _log_info "Creating target directory: $target"
            if ! mkdir -p "$target" 2>/dev/null; then
                local parent_dir
                parent_dir=$(dirname "$target")
                _handle_critical_error 1 "Cannot create target directory: $target" \
                    "Check parent directory permissions: chmod +w '$parent_dir'" \
                    "Parent directory: $parent_dir, Permissions: $(ls -lad "$parent_dir" 2>/dev/null | awk '{print $1}' || echo 'unknown')"
                return 1
            fi
        fi
        
        if [[ ! -w "$target" ]]; then
            _handle_critical_error 1 "Target directory is not writable: $target" \
                "Fix permissions: chmod +w '$target'" \
                "Current permissions: $(ls -lad "$target" 2>/dev/null | awk '{print $1}' || echo 'unknown')"
            return 1
        fi
        
        # 检查目标目录是否为空（给出警告）
        if [[ -d "$target" ]] && [[ -n "$(ls -A "$target" 2>/dev/null)" ]]; then
            _log_warning "Target directory is not empty: $target"
            _log_warning "Extraction may overwrite existing files"
        fi
        
        _clear_error_context
        return 0
    }
    
    # 检查路径冲突（简化版本）
    _check_path_conflicts() {
        local source="$1"
        local target="$2"
        
        # 获取规范化路径
        local source_realpath target_realpath
        source_realpath=$(realpath "$source" 2>/dev/null) || source_realpath="$source"
        target_realpath=$(realpath "$target" 2>/dev/null) || target_realpath="$target"
        
        # 检查源文件和目标文件是否相同
        if [[ "$source_realpath" == "$target_realpath" ]]; then
            _log_error "Source and target cannot be the same file: $source"
            return 1
        fi
        
        # 对于解压操作，只给出警告而不阻止
        if [[ "$action" == "extract" ]]; then
            local source_dir
            source_dir=$(dirname "$source_realpath")
            if [[ "$target_realpath" == "$source_dir" ]]; then
                _log_warning "Extracting to same directory as source file"
                _log_warning "Ensure extraction won't overwrite the source archive"
            fi
        fi
        
        return 0
    }
    
    # 检测归档是否包含tar包（简化列表优化版本）
    _is_tar_archive() {
        local archive="$1"
        
        # 使用全局命令变量，先用 7z 列表进行快速检查
        _log_info "Using simplified 7z list-based tar detection"
        
        # 构建7z列表命令参数数组（不包含密码）
        local list_args=("l" "-ba" "$archive")  # -ba = 简洁格式，更快速
        if [[ -n "${extra_7z_args:-}" ]]; then
            local -a extra_array
            extra_array=($(_split_args "$extra_7z_args"))
            list_args+=("${extra_array[@]}")
        fi
        
        # 检查归档内容列表（使用安全的密码传递方式）
        local archive_list
        if [[ -n "$password" ]]; then
            archive_list=$(_execute_7z_command "${list_args[@]}" 2>/dev/null)
            local list_exit_code=$?
        else
            archive_list=$("$sevenz_cmd" "${list_args[@]}" 2>/dev/null)
            local list_exit_code=$?
        fi
        
        # 如果列表失败，直接返回
        if [[ $list_exit_code -ne 0 || -z "$archive_list" ]]; then
            _log_info "7z list failed, assuming not tar format"
            return 1  # 无法读取归档，假设不是tar格式
        fi
        
        # 统计条目数量（过滤空行和无效条目）
        local total_entries=$(echo "$archive_list" | grep -v '^[[:space:]]*$' | grep -c '^')
        _log_info "Archive contains $total_entries entries"
        
        # 判断1: 多个文件或目录，肯定不是tar格式
        if [[ $total_entries -gt 1 ]]; then
            _log_info "Multiple entries ($total_entries), definitely not tar format"
            return 1  # 多个文件/目录，肯定不是tar格式
        fi
        
        # 判断2: 只有一个条目时，检查是否为目录
        if [[ $total_entries -eq 1 ]]; then
            local single_entry=$(echo "$archive_list" | grep -v '^[[:space:]]*$' | head -1)
            local single_file=$(echo "$single_entry" | awk '{print $NF}')
            _log_info "Single entry detected: $single_file"
            
            # 改进的目录检测逻辑
            # 1. 检查文件名是否以/结尾（明确的目录标识）
            # 2. 检查7z列表输出中的属性字段（通常第一个字段包含D标记）
            # 3. 检查文件大小是否为0且名称以/结尾
            local entry_attrs=$(echo "$single_entry" | awk '{print $1}')
            local entry_size=$(echo "$single_entry" | awk '{print $4}')
            
            if [[ "$single_file" == */ ]] || \
               [[ "$entry_attrs" == *"D"* ]] || \
               [[ "$entry_size" == "0" && "$single_file" == */ ]]; then
                _log_info "Single entry is a directory (file: $single_file, attrs: $entry_attrs, size: $entry_size), not tar format"
                return 1  # 目录不是tar格式
            fi
            
            # 单个文件，降级使用魔数检测
            _log_info "Single file detected, using magic number detection"
            _is_tar_archive_by_magic "$archive"
            return $?
        fi
        
        # 其他情况，认为不是tar格式
        _log_info "No valid entries found, not tar format"
        return 1
    }

    # 高性能tar检测（基于魔数和文件头分析）
    _is_tar_archive_by_magic() {
        local archive="$1"
        
        # 使用全局命令变量，构建7z命令读取文件头（读取足够的字节进行检测）
        local test_args=("x" "-so" "$archive")
        
        # 读取tar文件头进行魔数检测（读取1024字节以支持不同tar格式）
        local header
        if [[ -n "$password" ]]; then
            header=$(_execute_7z_command "${test_args[@]}" 2>/dev/null | head -c 1024)
        else
            header=$("$sevenz_cmd" "${test_args[@]}" 2>/dev/null | head -c 1024)
        fi
        
        if [[ -n "$header" ]]; then
            # 检查多种tar格式的魔数
            
            # 1. 检查POSIX tar格式 (ustar)
            local ustar_magic
            ustar_magic=$(echo -n "$header" | dd bs=1 skip=257 count=5 2>/dev/null)
            if [[ "$ustar_magic" == "ustar" ]]; then
                _log_info "POSIX TAR (ustar) magic number detected"
                return 0
            fi
            
            # 2. 检查GNU tar格式
            local gnu_magic
            gnu_magic=$(echo -n "$header" | dd bs=1 skip=257 count=8 2>/dev/null)
            if [[ "$gnu_magic" == "ustar  " ]] || [[ "$gnu_magic" == "ustar 00" ]]; then
                _log_info "GNU TAR magic number detected"
                return 0
            fi
            
            # # 3. 检查老式tar格式的特征（通过文件头结构验证）
            # # 老式tar没有魔数，但有固定的头结构
            # local file_mode file_size checksum
            # file_mode=$(echo -n "$header" | dd bs=1 skip=100 count=8 2>/dev/null | tr -d '\0')
            # file_size=$(echo -n "$header" | dd bs=1 skip=124 count=12 2>/dev/null | tr -d '\0')
            # checksum=$(echo -n "$header" | dd bs=1 skip=148 count=8 2>/dev/null | tr -d '\0')
            
            # # 检查是否为八进制数字（tar格式特征）
            # if [[ "$file_mode" =~ ^[0-7]+$ ]] && \
            #    [[ "$file_size" =~ ^[0-7]+$ ]] && \
            #    [[ "$checksum" =~ ^[0-7]+$ ]] && \
            #    [[ ${#file_mode} -le 8 ]] && \
            #    [[ ${#file_size} -le 12 ]] && \
            #    [[ ${#checksum} -le 8 ]]; then
            #     _log_info "Legacy TAR format detected (octal fields validated)"
            #     return 0
            # fi
            
            # # 4. 额外检查：验证tar块对齐（512字节边界）
            # local header_length=${#header}
            # if [[ $header_length -ge 512 ]]; then
            #     # 检查第二个块是否也符合tar格式
            #     local second_block_magic
            #     second_block_magic=$(echo -n "$header" | dd bs=1 skip=769 count=5 2>/dev/null)
            #     if [[ "$second_block_magic" == "ustar" ]]; then
            #         _log_info "Multi-block TAR structure detected"
            #         return 0
            #     fi
            # fi
        fi
        
        _log_info "No TAR magic number or structure found"
        return 1  # 不是tar格式
    }

    # 智能tar检测策略（简化版）
    _smart_tar_detection() {
        local archive="$1"
        
        _log_info "Using simplified tar detection strategy"
        
        # 使用简化的列表检测
        if _is_tar_archive "$archive"; then
            _log_info "Archive detected as tar format"
            return 0
        fi
        
        _log_info "Archive not detected as tar format, using direct 7z"
        return 1
    }
    
    # 构建7z参数数组的通用函数 - 使用返回方式避免eval
    # 注意：密码通过环境变量传递，不在命令行参数中显示
    _build_7z_args() {
        local -a base_args=("$@")
        
        if [[ -n "$password" ]]; then
            case "$1" in
                "a")  # 压缩操作
                    base_args+=("-mhe=on")
                    ;;
            esac
        fi
        
        if [[ -n "$extra_7z_args" ]]; then
            # 使用统一的参数分割函数
            local -a extra_array
            extra_array=($(_split_args "$extra_7z_args"))
            base_args+=("${extra_array[@]}")
        fi
        
        # 输出参数数组，供调用者使用
        printf '%s\n' "${base_args[@]}"
    }
    
    # 构建tar参数数组的通用函数
    _build_tar_args() {
        local base_operation="$1"  # 如 "c", "x", "t"
        local base_option="$2"     # 如 "f"
        local -a base_args=()
        
        if [[ -n "$extra_tar_args" ]]; then
            # 使用统一的参数分割函数，并将它们放在操作之前
            local -a extra_array
            extra_array=($(_split_args "$extra_tar_args"))
            base_args+=("${extra_array[@]}")
        fi
        
        # 操作参数放在额外参数之后
        base_args+=("-${base_operation}${base_option}")
        
        # 输出参数数组，供调用者使用
        printf '%s\n' "${base_args[@]}"
    }
    
    # 执行7z命令的通用函数（安全地通过环境变量传递密码）
    _execute_7z_command() {
        local -a cmd_args=("$@")
        
        # 构建安全的命令显示（隐藏密码）
        local display_cmd="$sevenz_cmd ${cmd_args[*]}"
        if [[ -n "$password" ]]; then
            display_cmd="$display_cmd [with password via environment]"
        fi
        _log_info "7z command: $display_cmd"
        
        # 如果有密码，通过环境变量传递
        if [[ -n "$password" ]]; then
            # 始终使用临时文件方式传递密码（最可靠的方法）
            _execute_7z_with_password_file "${cmd_args[@]}"
        else
            # 无密码情况直接执行
            "$sevenz_cmd" "${cmd_args[@]}"
        fi
        return $?
    }
    
    # 使用临时密码文件的安全方式 - 增强错误处理
    _execute_7z_with_password_file() {
        local -a cmd_args=("$@")
        _set_error_context "7z command with password file"
        
        # 创建临时密码文件
        local temp_password_file
        temp_password_file=$(mktemp "/tmp/.7zx_pass.XXXXXX") || {
            _handle_critical_error 1 "Failed to create temporary password file" \
                "Check /tmp directory permissions and available space" \
                "mktemp error in /tmp directory"
            return 1
        }
        
        # 注册清理文件
        _register_cleanup_file "$temp_password_file"
        
        # 设置安全权限（仅当前用户可读写）
        if ! chmod 600 "$temp_password_file"; then
            _handle_critical_error 1 "Failed to set secure permissions on password file" \
                "Check filesystem supports permission changes" \
                "chmod 600 failed on: $temp_password_file"
            return 1
        fi
        
        # 写入密码到临时文件
        if ! echo -n "$password" > "$temp_password_file"; then
            _handle_critical_error 1 "Failed to write password to temporary file" \
                "Check disk space and file permissions" \
                "Write operation failed: $temp_password_file"
            return 1
        fi
        
        # 验证密码文件内容
        if [[ ! -s "$temp_password_file" ]]; then
            _handle_critical_error 1 "Password file is empty after writing" \
                "Check if password variable is set correctly" \
                "Password length: ${#password} characters"
            return 1
        fi
        
        # 构建带密码文件的命令参数
        local -a final_args=()
        local password_added=false
        
        # 遍历原参数，在合适位置插入密码参数
        for arg in "${cmd_args[@]}"; do
            # 在 -si 或目标文件名之前插入密码参数
            if [[ "$arg" == "-si" ]] || [[ "$arg" == *.7z ]] && [[ "$password_added" == false ]]; then
                final_args+=("-p@$temp_password_file")
                password_added=true
            fi
            final_args+=("$arg")
        done
        
        # 如果还没有添加密码参数，在末尾添加
        if [[ "$password_added" == false ]]; then
            final_args+=("-p@$temp_password_file")
        fi
        
        _log_debug "Executing 7z command with password file"
        
        # 执行7z命令
        "$sevenz_cmd" "${final_args[@]}"
        local exit_code=$?
        
        # 立即清理密码文件
        _secure_file_cleanup "$temp_password_file"
        
        if [[ $exit_code -ne 0 ]]; then
            case $exit_code in
                1) _log_error "7z: Warning (Non fatal error(s))" ;;
                2) _log_error "7z: Fatal error" ;;
                7) _log_error "7z: Command line error" ;;
                8) _log_error "7z: Not enough memory for operation" ;;
                255) _log_error "7z: User stopped the process" ;;
                *) _log_error "7z: Unknown error (exit code: $exit_code)" ;;
            esac
        fi
        
        _clear_error_context
        return $exit_code
    }
    
    # 安全清理密码文件 - 已集成到 _secure_file_cleanup
    _cleanup_password_file() {
        local password_file="$1"
        _secure_file_cleanup "$password_file"
    }
    
    # 自动生成密码函数 - 增强错误处理
    _generate_password_if_needed() {
        if [[ "$gen_pass" == true ]]; then
            _set_error_context "password generation"
            
            # 检查 gen_pass 命令是否存在
            if ! command -v gen_pass >/dev/null 2>&1; then
                _handle_critical_error 1 "gen_pass command not found" \
                    "Install gen_pass or make it available in PATH" \
                    "Required for --gen-pass option"
                return 1
            fi
            
            local input_file=""
            case "$action" in
                "compress")
                    if [[ -n "$target" ]]; then
                        input_file="$target"
                    else
                        _handle_critical_error 1 "No target specified for password generation" \
                            "Provide target filename for --gen-pass" \
                            "Target required for compress operation"
                        return 1
                    fi
                    ;;
                "extract"|"list"|"info")
                    if [[ -n "$source" ]]; then
                        input_file="$source"
                    else
                        _handle_critical_error 1 "No source specified for password generation" \
                            "Provide source filename for --gen-pass" \
                            "Source required for $action operation"
                        return 1
                    fi
                    ;;
                *)
                    _handle_critical_error 1 "Invalid action for password generation: $action" \
                        "Use --gen-pass with compress, extract, list, or info actions" \
                        "Unsupported action"
                    return 1
                    ;;
            esac
            
            _log_info "Generating password for: $input_file"
            local gen_output
            if gen_output=$(gen_pass -i "$input_file" 2>&1); then
                password="$gen_output"
                _log_info "Password generated successfully (length: ${#password} characters)"
            else
                _handle_critical_error 1 "Failed to generate password for: $input_file" \
                    "Check gen_pass installation and input file" \
                    "gen_pass output: $gen_output"
                return 1
            fi
            
            _clear_error_context
        fi
        return 0
    }

    # 决定是否使用tar的函数（考虑--no-tar优先级和智能检测）
    _should_use_tar() {
        local archive="$1"
        
        # --no-tar 参数具有最高优先级
        if [[ "$use_tar" == false ]]; then
            _log_info "Skipping tar detection due to --no-tar flag"
            return 1  # 不使用tar
        fi
        
        # 智能tar检测策略
        _smart_tar_detection "$archive"
        return $?
    }

    # 压缩功能的内部函数 - 增强错误处理
    _compress_with_tar() {
        local src="$1" tgt="$2"
        _set_error_context "tar+7z compression: $src -> $tgt"
        
        _log_info "Compressing with $tar_cmd + 7z: $src -> $tgt"
        
        local target_existed=false
        [[ -f "$tgt" ]] && target_existed=true
        
        # 检查源文件大小估算
        local estimated_size=0
        if command -v du >/dev/null 2>&1; then
            estimated_size=$(du -sb "$src" 2>/dev/null | cut -f1 || echo "0")
            if [[ $estimated_size -gt 0 ]]; then
                _log_info "Source size: $(numfmt --to=iec $estimated_size 2>/dev/null || echo "$estimated_size bytes")"
            fi
        fi
        
        local -a sevenz_args
        sevenz_args=($(_build_7z_args "a" "-t7z" "-m0=lzma2" "-mx=9" "-si" "$tgt"))
        
        local -a tar_args
        tar_args=($(_build_tar_args "c" "f"))
        
        # 支持多个源文件
        local -a src_files
        src_files=(${=src})  # zsh word splitting
        
        _log_debug "Tar command: $tar_cmd ${tar_args[*]} - ${src_files[*]}"
        _log_debug "7z command: $sevenz_cmd ${sevenz_args[*]}"
        
        # 使用管道执行tar+7z，增加错误检测
        if ! "$tar_cmd" "${tar_args[@]}" - "${src_files[@]}" 2>/dev/null | _execute_7z_command "${sevenz_args[@]}"; then
            local tar_exit_code=${PIPESTATUS[1]:-1}
            local sevenz_exit_code=${PIPESTATUS[2]:-1}
            
            _log_error "Tar+7z compression failed"
            [[ $tar_exit_code -ne 0 ]] && _log_error "Tar error (exit code: $tar_exit_code)"
            [[ $sevenz_exit_code -ne 0 ]] && _log_error "7z error (exit code: $sevenz_exit_code)"
            
            _cleanup_failed_target "$tgt" "$target_existed"
            _clear_error_context
            return 1
        fi
        
        # 验证输出文件
        if [[ ! -f "$tgt" ]] || [[ ! -s "$tgt" ]]; then
            _handle_critical_error 1 "Compression completed but output file is missing or empty" \
                "Check disk space and permissions" \
                "Target file: $tgt"
            _cleanup_failed_target "$tgt" "$target_existed"
            return 1
        fi
        
        # 显示压缩结果
        local final_size
        final_size=$(stat -c%s "$tgt" 2>/dev/null || stat -f%z "$tgt" 2>/dev/null || echo "0")
        if [[ $estimated_size -gt 0 && $final_size -gt 0 ]]; then
            local ratio=$((final_size * 100 / estimated_size))
            _log_ok "Tar+7z compression completed: $tgt (compression ratio: $ratio%)"
        else
            _log_ok "Tar+7z compression completed: $tgt"
        fi
        
        [[ "$verbose" == true ]] && ls -lh "$tgt" >&2
        _clear_error_context
        return 0
    }
    
    _compress_direct() {
        local src="$1" tgt="$2"
        _set_error_context "direct 7z compression: $src -> $tgt"
        
        _log_info "Direct 7z compression: $src -> $tgt"
        
        local target_existed=false
        [[ -f "$tgt" ]] && target_existed=true
        
        # 支持多个源文件
        local -a src_files
        src_files=(${=src})  # zsh word splitting
        
        # 检查源文件大小
        local total_size=0
        for src_file in "${src_files[@]}"; do
            if [[ -f "$src_file" ]]; then
                local file_size
                file_size=$(stat -c%s "$src_file" 2>/dev/null || stat -f%z "$src_file" 2>/dev/null || echo "0")
                total_size=$((total_size + file_size))
            elif [[ -d "$src_file" ]]; then
                if command -v du >/dev/null 2>&1; then
                    local dir_size
                    dir_size=$(du -sb "$src_file" 2>/dev/null | cut -f1 || echo "0")
                    total_size=$((total_size + dir_size))
                fi
            fi
        done
        
        if [[ $total_size -gt 0 ]]; then
            _log_info "Total source size: $(numfmt --to=iec $total_size 2>/dev/null || echo "$total_size bytes")"
        fi
        
        local -a sevenz_args
        sevenz_args=($(_build_7z_args "a" "-t7z" "-m0=lzma2" "-mx=9" "$tgt" "${src_files[@]}"))
        
        _log_debug "7z command: $sevenz_cmd ${sevenz_args[*]}"
        
        if ! _execute_7z_command "${sevenz_args[@]}"; then
            _log_error "Direct 7z compression failed"
            _cleanup_failed_target "$tgt" "$target_existed"
            _clear_error_context
            return 1
        fi
        
        # 验证输出文件
        if [[ ! -f "$tgt" ]] || [[ ! -s "$tgt" ]]; then
            _handle_critical_error 1 "Compression completed but output file is missing or empty" \
                "Check disk space and permissions" \
                "Target file: $tgt"
            _cleanup_failed_target "$tgt" "$target_existed"
            return 1
        fi
        
        # 显示压缩结果
        local final_size
        final_size=$(stat -c%s "$tgt" 2>/dev/null || stat -f%z "$tgt" 2>/dev/null || echo "0")
        if [[ $total_size -gt 0 && $final_size -gt 0 ]]; then
            local ratio=$((final_size * 100 / total_size))
            _log_ok "Direct 7z compression completed: $tgt (compression ratio: $ratio%)"
        else
            _log_ok "Direct 7z compression completed: $tgt"
        fi
        
        [[ "$verbose" == true ]] && ls -lh "$tgt" >&2
        _clear_error_context
        return 0
    }
    
    _cleanup_failed_target() {
        local target="$1" existed="$2"
        
        # 只有在压缩失败且目标文件之前不存在或大小为0时才删除
        if [[ "$existed" == false ]] || [[ ! -s "$target" ]]; then
            if [[ -f "$target" ]]; then
                local file_size
                file_size=$(stat -c%s "$target" 2>/dev/null || stat -f%z "$target" 2>/dev/null || echo "0")
                _log_warning "Removing incomplete target file: $target (size: $file_size bytes)"
                rm -f "$target" 2>/dev/null
            fi
        else
            _log_warning "Keeping existing target file: $target"
        fi
    }
    
    # 提取功能的内部函数（改进的临时文件管理和错误处理）
    _extract_with_tar() {
        local src="$1" tgt="$2"
        _set_error_context "tar+7z extraction: $src -> $tgt"
        
        local -a sevenz_args
        sevenz_args=($(_build_7z_args "x" "-so" "$src"))
        
        _log_info "Extracting with $tar_cmd: $src -> $tgt"
        
        # 创建更安全的临时文件
        local temp_tar
        temp_tar=$(mktemp "/tmp/7zx_temp_XXXXXX.tar") || {
            _handle_critical_error 1 "Failed to create temporary file" \
                "Check /tmp directory permissions and space" \
                "mktemp failed for tar extraction"
            return 1
        }
        
        # 注册清理文件
        _register_cleanup_file "$temp_tar"
        
        _log_debug "Using temporary file: $temp_tar"
        _log_debug "7z extract command: $sevenz_cmd ${sevenz_args[*]}"
        
        # 执行7z解压到临时文件
        if ! _execute_7z_command "${sevenz_args[@]}" > "$temp_tar"; then
            _handle_critical_error 1 "7z extraction to temporary file failed" \
                "Check archive integrity and password" \
                "Failed to extract tar content from 7z archive"
            return 1
        fi
        
        # 验证临时tar文件
        if [[ ! -s "$temp_tar" ]]; then
            _handle_critical_error 1 "Temporary tar file is empty" \
                "Archive may be corrupted or password incorrect" \
                "Extracted tar size: 0 bytes"
            return 1
        fi
        
        local temp_size
        temp_size=$(stat -c%s "$temp_tar" 2>/dev/null || stat -f%z "$temp_tar" 2>/dev/null || echo "0")
        _log_info "Extracted tar size: $(numfmt --to=iec $temp_size 2>/dev/null || echo "$temp_size bytes")"
        
        # 使用tar解压临时文件
        local -a tar_args
        tar_args=($(_build_tar_args "x" "f"))
        
        _log_debug "Tar extract command: $tar_cmd ${tar_args[*]} $temp_tar -C $tgt"
        
        if ! "$tar_cmd" "${tar_args[@]}" "$temp_tar" -C "$tgt" 2>/dev/null; then
            _handle_critical_error 1 "Tar extraction failed" \
                "Check target directory permissions and disk space" \
                "Failed to extract from temporary tar file"
            return 1
        fi
        
        # 清理临时文件
        _secure_file_cleanup "$temp_tar"
        
        _log_ok "Tar+7z extraction completed to: $tgt"
        _clear_error_context
        return 0
    }
    
    _extract_direct() {
        local src="$1" tgt="$2"
        _set_error_context "direct 7z extraction: $src -> $tgt"
        
        local -a sevenz_args
        sevenz_args=($(_build_7z_args "x" "-o$tgt" "$src"))
        
        _log_info "Direct 7z extraction: $src -> $tgt"
        _log_debug "7z command: $sevenz_cmd ${sevenz_args[*]}"
        
        if ! _execute_7z_command "${sevenz_args[@]}"; then
            _handle_critical_error 1 "Direct 7z extraction failed" \
                "Check archive integrity, password, and target permissions" \
                "Failed to extract archive directly"
            return 1
        fi
        
        # 验证解压结果
        if [[ ! -d "$tgt" ]] || [[ -z "$(ls -A "$tgt" 2>/dev/null)" ]]; then
            _handle_critical_error 1 "Extraction completed but target directory is empty" \
                "Archive may be empty or extraction path incorrect" \
                "Target directory: $tgt"
            return 1
        fi
        
        _log_ok "Direct 7z extraction completed to: $tgt"
        _clear_error_context
        return 0
    }
    
    # 列表功能的内部函数
    _list_tar_archive() {
        local src="$1"
        local -a sevenz_args
        sevenz_args=($(_build_7z_args "x" "-so" "$src"))
        
        _log_info "Listing tar-packed archive with $tar_cmd: $src"
        
        local -a tar_args
        tar_args=($(_build_tar_args "t" "f"))
        
        if _execute_7z_command "${sevenz_args[@]}" | "$tar_cmd" "${tar_args[@]}" -; then
            return 0
        else
            _log_error "Failed to list tar-packed contents"
            return 1
        fi
    }
    
    _list_direct_archive() {
        local src="$1"
        local -a sevenz_args
        sevenz_args=($(_build_7z_args "l" "$src"))
        
        _log_info "Listing direct 7z archive: $src"
        _execute_7z_command "${sevenz_args[@]}"
        return $?
    }
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--compress)
                # 压缩需要至少3个参数：-c SOURCE TARGET
                if [[ $# -lt 3 ]]; then
                    echo "[ERROR] compress requires SOURCE and TARGET arguments" >&2
                    echo "Usage: 7zx -c SOURCE TARGET [OPTIONS]" >&2
                    return 1
                fi
                if [[ -z "$2" || -z "$3" ]]; then
                    echo "[ERROR] compress requires non-empty SOURCE and TARGET" >&2
                    return 1
                fi
                if [[ "$2" == -* || "$3" == -* ]]; then
                    echo "[ERROR] SOURCE and TARGET cannot start with '-' (looks like options)" >&2
                    echo "If your file really starts with '-', use './SOURCE' or './TARGET'" >&2
                    return 1
                fi
                action="compress"
                source="$2"
                target="$3"
                shift 3
                ;;
            -x|--extract)
                # 解压需要至少2个参数：-x SOURCE [TARGET]
                if [[ $# -lt 2 ]]; then
                    echo "[ERROR] extract requires SOURCE argument" >&2
                    echo "Usage: 7zx -x SOURCE [TARGET] [OPTIONS]" >&2
                    return 1
                fi
                if [[ -z "$2" ]]; then
                    echo "[ERROR] extract requires non-empty SOURCE" >&2
                    return 1
                fi
                if [[ "$2" == -* ]]; then
                    echo "[ERROR] SOURCE cannot start with '-' (looks like an option)" >&2
                    echo "If your file really starts with '-', use './SOURCE'" >&2
                    return 1
                fi
                action="extract"
                source="$2"
                # 检查第三个参数是否是选项（以-开头）
                if [[ -n "$3" && "$3" != -* ]]; then
                    target="$3"
                    shift 3
                else
                    target="."  # 默认当前目录
                    shift 2
                fi
                ;;
            -l|--list)
                # 列表需要2个参数：-l ARCHIVE
                if [[ $# -lt 2 ]]; then
                    echo "[ERROR] list requires ARCHIVE argument" >&2
                    echo "Usage: 7zx -l ARCHIVE [OPTIONS]" >&2
                    return 1
                fi
                if [[ -z "$2" ]]; then
                    echo "[ERROR] list requires non-empty ARCHIVE" >&2
                    return 1
                fi
                if [[ "$2" == -* ]]; then
                    echo "[ERROR] ARCHIVE cannot start with '-' (looks like an option)" >&2
                    echo "If your file really starts with '-', use './your_filename'" >&2
                    return 1
                fi
                action="list"
                source="$2"
                shift 2
                ;;
            -i|--info)
                # 信息需要2个参数：-i ARCHIVE
                if [[ $# -lt 2 ]]; then
                    echo "[ERROR] info requires ARCHIVE argument" >&2
                    echo "Usage: 7zx -i ARCHIVE [OPTIONS]" >&2
                    return 1
                fi
                if [[ -z "$2" ]]; then
                    echo "[ERROR] info requires non-empty ARCHIVE" >&2
                    return 1
                fi
                if [[ "$2" == -* ]]; then
                    echo "[ERROR] ARCHIVE cannot start with '-' (looks like an option)" >&2
                    echo "If your file really starts with '-', use './your_filename'" >&2
                    return 1
                fi
                action="info"
                source="$2"
                shift 2
                ;;
            -p|--password)
                # 密码需要2个参数：-p PASSWORD
                if [[ $# -lt 2 ]]; then
                    echo "[ERROR] password option requires PASSWORD argument" >&2
                    echo "Usage: 7zx [ACTION] -p PASSWORD" >&2
                    return 1
                fi
                if [[ -z "$2" ]]; then
                    echo "[ERROR] password cannot be empty" >&2
                    return 1
                fi
                password="$2"
                shift 2
                ;;
            -a|--args)
                # 额外7z参数需要2个参数：-a "ARGS"
                if [[ $# -lt 2 ]]; then
                    echo "[ERROR] args option requires ARGS argument" >&2
                    echo "Usage: 7zx [ACTION] -a \"ARGS\"" >&2
                    return 1
                fi
                if [[ -z "$2" ]]; then
                    echo "[ERROR] args cannot be empty" >&2
                    return 1
                fi
                extra_7z_args="$2"
                shift 2
                ;;
            --7z-args)
                # 专门给7z的额外参数
                if [[ $# -lt 2 ]]; then
                    echo "[ERROR] --7z-args option requires ARGS argument" >&2
                    echo "Usage: 7zx [ACTION] --7z-args \"ARGS\"" >&2
                    return 1
                fi
                if [[ -z "$2" ]]; then
                    echo "[ERROR] 7z args cannot be empty" >&2
                    return 1
                fi
                extra_7z_args="$2"
                shift 2
                ;;
            --tar-args)
                # 专门给tar的额外参数
                if [[ $# -lt 2 ]]; then
                    echo "[ERROR] --tar-args option requires ARGS argument" >&2
                    echo "Usage: 7zx [ACTION] --tar-args \"ARGS\"" >&2
                    return 1
                fi
                if [[ -z "$2" ]]; then
                    echo "[ERROR] tar args cannot be empty" >&2
                    return 1
                fi
                extra_tar_args="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --no-tar)
                use_tar=false
                shift
                ;;
            --gen-pass)
                gen_pass=true
                shift
                ;;
            -h|--help)
                cat <<'EOF'
Usage: 7zx [ACTION] [OPTIONS]

ACTIONS:
  -c, --compress SOURCE TARGET    Compress SOURCE to TARGET
  -x, --extract SOURCE [TARGET]   Extract SOURCE to TARGET (default: current dir)
  -l, --list ARCHIVE             List contents of ARCHIVE
  -i, --info ARCHIVE             Show archive information

OPTIONS:
  -p, --password PASSWORD        Set password for encryption/decryption
  -a, --args "ARGS"             Pass additional 7z arguments (legacy)
  --7z-args "ARGS"              Pass arguments specifically to 7z command
  --tar-args "ARGS"             Pass arguments specifically to tar command
  -v, --verbose                 Enable verbose output
  --no-tar                      Skip tar packing (direct 7z compression)
  --gen-pass                    Auto-generate password from file paths
  -h, --help                    Show this help message

EXAMPLES:
  7zx -c /root backup.7z -p "mypassword"
  7zx -c /root backup.7z --no-tar -p "mypassword"
  7zx -c /root backup.7z --gen-pass  # uses backup.7z as password
  7zx -c /root backup.7z --7z-args "-mx=9 -mmt=4"
  7zx -c /root backup.7z --tar-args "--exclude='*.log'"
  7zx -c /var/log backup.7z --tar-args "--ignore-failed-read --exclude='*.tmp'"
  7zx -x backup.7z /tmp/restore -p "mypassword"
  7zx -x backup.7z --gen-pass  # uses backup.7z as password
  7zx -x backup.7z  # extract to current directory
  7zx -l backup.7z
  7zx -i backup.7z -p "mypassword"

TAR COMMAND DETECTION:
  The script automatically detects and uses gtar (GNU tar) if available,
  falling back to standard tar command if gtar is not found.
EOF
                return 0
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                return 1
                ;;
        esac
    done
    
    # 统一验证函数 - 增强错误处理
    _validate_action_requirements() {
        local action="$1" source="$2" target="$3"
        _set_error_context "action requirements validation: $action"
        
        case "$action" in
            "compress")
                if ! _validate_source_path "$source"; then
                    _log_error "Source validation failed for compress operation"
                    return 1
                fi
                if ! _validate_target_directory "$target"; then
                    _log_error "Target validation failed for compress operation"
                    return 1
                fi
                if ! _check_path_conflicts "$source" "$target"; then
                    _log_error "Path conflict detected for compress operation"
                    return 1
                fi
                if [[ -f "$target" ]]; then
                    _log_warning "Target file already exists: $target"
                    _log_warning "Will overwrite existing file"
                fi
                ;;
            "extract")
                if ! _validate_source_file "$source"; then
                    _log_error "Source validation failed for extract operation"
                    return 1
                fi
                if ! _validate_extract_target "$target"; then
                    _log_error "Extract target validation failed"
                    return 1
                fi
                if ! _check_path_conflicts "$source" "$target"; then
                    _log_error "Path conflict detected for extract operation"
                    return 1
                fi
                ;;
            "list"|"info")
                if ! _validate_source_file "$source"; then
                    _log_error "Source validation failed for $action operation"
                    return 1
                fi
                ;;
            *)
                _handle_critical_error 1 "Unknown action: $action" \
                    "Valid actions: compress, extract, list, info" \
                    "Invalid action in validation"
                return 1
                ;;
        esac
        
        _clear_error_context
        return 0
    }

    # 密码验证逻辑 - 增强错误信息
    _validate_password_options() {
        _set_error_context "password validation"
        
        # 验证password和gen_pass不能同时使用
        if [[ -n "$password" && "$gen_pass" == true ]]; then
            _handle_critical_error 1 "Cannot use both -p/--password and --gen-pass at the same time" \
                "Choose either manual password (-p) or auto-generated password (--gen-pass)" \
                "Conflicting password options specified"
            return 1
        fi
        
        # 验证手动密码的强度（如果提供）
        if [[ -n "$password" ]]; then
            local password_length=${#password}
            if [[ $password_length -lt 4 ]]; then
                _log_warning "Password is very short (${password_length} characters) - consider using a longer password"
            elif [[ $password_length -ge 12 ]]; then
                _log_info "Strong password detected (${password_length} characters)"
            fi
        fi
        
        # 对于需要密码的操作，确保有密码来源
        if [[ "$action" =~ ^(compress|extract|list|info)$ ]]; then
            if [[ -z "$password" && "$gen_pass" == false ]]; then
                if [[ "$action" == "compress" ]]; then
                    _log_info "No password specified, archive will be unencrypted"
                    _log_warning "Consider using -p or --gen-pass for encrypted archives"
                else
                    _log_info "No password specified, assuming unencrypted archive"
                fi
            fi
        fi
        
        _clear_error_context
        return 0
    }
    
    # ===== 主执行流程 =====
    
    # 0. 设置统一陷阱管理
    _setup_global_trap
    
    # 1. 验证必需参数
    if [[ -z "$action" ]]; then
        _handle_critical_error 1 "No action specified" \
            "Use -h for help" \
            "Valid actions: -c (compress), -x (extract), -l (list), -i (info)"
        return 1
    fi
    
    # 根据不同的动作进行参数校验
    case "$action" in
        "compress")
            if [[ -z "$source" ]] || [[ -z "$target" ]]; then
                _handle_critical_error 1 "compress action requires both SOURCE and TARGET" \
                    "Usage: 7zx -c SOURCE TARGET [OPTIONS]" \
                    "Missing required parameters"
                return 1
            fi
            ;;
        "extract"|"list"|"info")
            if [[ -z "$source" ]]; then
                _handle_critical_error 1 "$action action requires SOURCE" \
                    "Usage: 7zx -$action SOURCE [OPTIONS]" \
                    "Missing required source parameter"
                return 1
            fi
            ;;
    esac
    
    # 2. 验证密码选项
    _validate_password_options || return 1
    
    # 3. 检测命令依赖（使用全局变量，避免重复检测）
    _detect_7z_command || return 1
    _detect_tar_command || return 1
    
    _log_info "Using 7z command: $sevenz_cmd"
    _log_info "Using tar command: $tar_cmd"
    
    # 4. 生成密码（如果需要）
    _generate_password_if_needed || return 1
    
    # 5. 执行相应操作 - 增强错误处理
    case "$action" in
        "compress")
            _set_error_context "compress operation"
            # 验证操作要求
            _validate_action_requirements "$action" "$source" "$target" || return 1
            # 根据--no-tar参数决定压缩方式
            if [[ "$use_tar" == true ]]; then
                _compress_with_tar "$source" "$target"
            else
                _compress_direct "$source" "$target"
            fi
            local compress_result=$?
            _clear_error_context
            return $compress_result
            ;;
            
        "extract")
            _set_error_context "extract operation"
            # 验证操作要求
            _validate_action_requirements "$action" "$source" "$target" || return 1
            # 根据--no-tar参数和tar检测决定解压方式
            if _should_use_tar "$source"; then
                _log_info "Detected tar-packed archive, will unpack with tar"
                _extract_with_tar "$source" "$target"
            else
                _log_info "Direct 7z archive detected, extracting directly"
                _extract_direct "$source" "$target"
            fi
            local extract_result=$?
            _clear_error_context
            return $extract_result
            ;;
            
        "list")
            _set_error_context "list operation"
            # 验证操作要求
            _validate_action_requirements "$action" "$source" "$target" || return 1
            # 根据--no-tar参数和tar检测决定列表方式
            if _should_use_tar "$source"; then
                _list_tar_archive "$source"
            else
                _list_direct_archive "$source"
            fi
            local list_result=$?
            _clear_error_context
            return $list_result
            ;;
            
        "info")
            _set_error_context "info operation"
            # 验证操作要求
            _validate_action_requirements "$action" "$source" "$target" || return 1
            local -a sevenz_args
            sevenz_args=($(_build_7z_args "l" "$source"))
            
            _log_info "Archive information for $source"
            _execute_7z_command "${sevenz_args[@]}"
            local info_result=$?
            _clear_error_context
            return $info_result
            ;;
            
        *)
            _handle_critical_error 1 "Unknown action: $action" \
                "Valid actions: compress, extract, list, info" \
                "Invalid action parameter"
            return 1
            ;;
    esac
}
