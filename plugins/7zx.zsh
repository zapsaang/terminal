7zx() {
    declare -A inner_config=(
        [action]=""
        [source]=""
        [target]=""
        [password]=""
        [verbose]=false
        [use_tar]=true
        [force_tar]=false
        [gen_pass]=false
        [extra_7z_args]=""
        [extra_tar_args]=""
        [exclude_patterns]=""
    )
    
    local -a _7z_args
    
    declare -A inner_commands=(
        [sevenz]=""
        [tar]=""
    )
    
    local -a cleanup_files=()
    local operation_start_time=""
    
    _handle_error() {
        local exit_code=${1:-1}
        local error_msg="$2"
        local suggestion="${3:-}"
        
        _log_error "$error_msg"
        [[ -n "$suggestion" ]] && _log_error "Suggestion: $suggestion"
        
        return $exit_code
    }
    
    _setup_cleanup() {
        operation_start_time=$(date +%s)
        trap '_cleanup_and_exit $? EXIT' EXIT
        trap '_cleanup_and_exit $? INT' INT
        trap '_cleanup_and_exit $? TERM' TERM
    }
    
    _cleanup_and_exit() {
        local exit_code=${1:-0}
        local signal=${2:-"EXIT"}
        
        if [[ -n "$operation_start_time" && "$inner_config[verbose]" == true ]]; then
            local duration=$(($(date +%s) - operation_start_time))
            _log_info "Operation duration: ${duration}s"
        fi
        
        for temp_file in "${cleanup_files[@]}"; do
            [[ -f "$temp_file" ]] && _secure_cleanup "$temp_file"
        done
        
        trap - EXIT INT TERM
        
        if [[ "$signal" != "EXIT" && $exit_code -ne 0 ]]; then
            _log_error "Operation interrupted by signal: $signal"
            exit 130
        fi
    }
    
    _register_cleanup() {
        cleanup_files+=("$1")
    }
    
    _secure_cleanup() {
        local file="$1"
        if [[ -f "$file" ]]; then
            if [[ "$file" == *"pass"* || "$file" == *"secret"* ]]; then
                dd if=/dev/urandom of="$file" bs=1024 count=1 2>/dev/null || true
            fi
            rm -f "$file" 2>/dev/null
            _log_debug "Cleaned up: $file"
        fi
    }

    
    
    _initialize_commands() {
        if [[ -z "${inner[sevenz]}" ]]; then
            if _command_exists "7zz"; then
                inner_commands[sevenz]="7zz"
                _log_info "Found 7zz command"
            elif _command_exists "7z"; then
                inner_commands[sevenz]="7z"
                _log_info "Found 7z command"
            else
                _handle_error 1 "No 7z command found" "Install 7-Zip: brew install p7zip"
                return 1
            fi
            
            if ! "${inner_commands[sevenz]}" --help >/dev/null 2>&1; then
                _handle_error 1 "7z command is not working properly" "Reinstall 7-Zip"
                return 1
            fi
        fi
        
        if [[ -z "${inner_commands[tar]}" ]]; then
            if _command_exists "gtar"; then
                inner_commands[tar]="gtar"
                _log_info "Found GNU tar"
            elif _command_exists "tar"; then
                inner_commands[tar]="tar"
                _log_info "Found tar"
            else
                _handle_error 1 "No tar command found" "Install tar command"
                return 1
            fi
        fi
        
        return 0
    }
    
    
    _get_timestamp() {
        date '+%H:%M:%S' 2>/dev/null || echo ''
    }
    
    _get_file_size() {
        local file="$1"
        stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0"
    }
    
    _format_size() {
        local size="$1"
        if [[ $size -gt 0 ]]; then
            if command -v numfmt >/dev/null 2>&1; then
                numfmt --to=iec "$size" 2>/dev/null || echo "${size} bytes"
            else
                if [[ $size -ge 1073741824 ]]; then
                    echo "$(( size / 1073741824 ))G"
                elif [[ $size -ge 1048576 ]]; then
                    echo "$(( size / 1048576 ))M"
                elif [[ $size -ge 1024 ]]; then
                    echo "$(( size / 1024 ))K"
                else
                    echo "${size} bytes"
                fi
            fi
        else
            echo "0 bytes"
        fi
    }
    
    _command_exists() {
        local cmd="$1"
        if (( $+commands[$cmd] )); then
            return 0
        fi
        if (( $+functions[$cmd] )); then
            return 0
        fi
        if (( $+aliases[$cmd] )); then
            return 0
        fi
        return 1
    }
    
    _log() {
        local level="$1"
        shift
        local timestamp=$(_get_timestamp)
        local show_log=true
        
        case "$level" in
            "INFO"|"WARNING"|"DEBUG")
                [[ "${inner_config[verbose]}" != true ]] && show_log=false
                ;;
            "ERROR"|"OK")
                show_log=true
                ;;
        esac
        
        if [[ "$show_log" == true ]]; then
            if [[ "$level" == "OK" ]]; then
                echo "[$level $timestamp] $*"
            else
                echo "[$level $timestamp] $*" >&2
            fi
        fi
    }
    
    _log_info() { _log "INFO" "$@"; }
    _log_error() { _log "ERROR" "$@"; }
    _log_ok() { _log "OK" "$@"; }
    _log_warning() { _log "WARNING" "$@"; }
    _log_debug() { _log "DEBUG" "$@"; }

    
    _validate_source_file() {
        local file="$1"
        
        if [[ ! -f "$file" ]]; then
            _handle_error 1 "Source file does not exist: $file"
            return 1
        fi
        
        if [[ ! -r "$file" ]]; then
            _handle_error 1 "Source file is not readable: $file"
            return 1
        fi
        
        if [[ ! -s "$file" ]]; then
            _handle_error 1 "Source file is empty: $file"
            return 1
        fi
        
        _log_debug "Source file validated: $file ($(_format_size $(_get_file_size "$file")))"
        return 0
    }
    
    _safe_split_paths() {
        local input="$1"
        
        if [[ "$input" == *"\\ "* ]]; then
            echo "${input//\\ / }"
            return
        fi
        
        local -a parts=( ${=input} )
        
        if [[ ${#parts[@]} -eq 1 ]]; then
            echo "$input"
            return
        fi
        
        for part in "${parts[@]}"; do
            echo "$part"
        done
    }
    
    _validate_source_path() {
        local source_path="$1"
        local -a source_paths
        while IFS= read -r line; do
            source_paths+=("$line")
        done < <(_safe_split_paths "$source_path")
        
        for source_item in "${source_paths[@]}"; do
            if [[ ! -e "$source_item" ]]; then
                _handle_error 1 "Source path does not exist: $source_item"
                return 1
            fi
        done
        
        _log_debug "Source paths validated: ${#source_paths[@]} items"
        return 0
    }
    
    _validate_target_directory() {
        local target="$1"
        local target_dir=$(dirname "$target")
        
        if [[ ! -d "$target_dir" ]]; then
            _handle_error 1 "Target directory does not exist: $target_dir"
            return 1
        fi
        
        if [[ ! -w "$target_dir" ]]; then
            _handle_error 1 "Target directory is not writable: $target_dir"
            return 1
        fi
        
        return 0
    }
    
    _validate_extract_target() {
        local target="$1"
        
        if [[ "$target" == *../* ]]; then
            _handle_error 1 "Target contains path traversal: $target"
            return 1
        fi
        
        if [[ ! -d "$target" ]]; then
            mkdir -p "$target" || {
                _handle_error 1 "Cannot create target directory: $target"
                return 1
            }
        fi
        
        if [[ ! -w "$target" ]]; then
            _handle_error 1 "Target directory is not writable: $target"
            return 1
        fi
        
        return 0
    }
    

    
    _should_use_tar_for_compression() {
        local source="$1"
        
        if [[ "${inner_config[use_tar]}" == false ]]; then
            _log_debug "Not using tar due to --no-tar flag"
            return 1
        fi
        
        if [[ "${inner_config[force_tar]}" == true ]]; then
            _log_debug "Using tar due to --force-tar flag"
            return 0
        fi
        
        local -a src_files
        while IFS= read -r line; do
            src_files+=("$line")
        done < <(_safe_split_paths "$source")
        
        if [[ ${#src_files[@]} -eq 1 && ! -d "${src_files[1]}" ]]; then
            _log_debug "Single file detected, not using tar"
            return 1
        fi
        
        _log_debug "Multiple files or directory detected, using tar"
        return 0
    }

    _is_tar_archive() {
        local archive="$1"
        
        if [[ "${inner_config[use_tar]}" == false ]]; then
            _log_debug "Skipping tar detection due to --no-tar flag"
            return 1
        fi
        
        if [[ "${inner_config[force_tar]}" == true ]]; then
            _log_debug "Forcing tar mode due to --force-tar flag"
            return 0
        fi
        
        _log_debug "Checking if archive contains tar data"
        
        local -a list_args=("l" "-ba" "$archive")
        
        local archive_list
        if [[ -n "${inner_config[password]}" ]]; then
            archive_list=$(_execute_7z_with_password "${list_args[@]}" 2>/dev/null)
        else
            archive_list=$("${inner_commands[sevenz]}" "${list_args[@]}" 2>/dev/null)
        fi
        
        [[ -z "$archive_list" ]] && return 1
        
        local entry_count=$(echo "$archive_list" | grep -v '^[[:space:]]*$' | wc -l)
        
        if [[ $entry_count -gt 1 ]]; then
            _log_debug "Multiple entries ($entry_count), not tar format"
            return 1
        fi
        
        if [[ $entry_count -eq 1 ]]; then
            local entry=$(echo "$archive_list" | grep -v '^[[:space:]]*$' | head -1)
            local filename=$(echo "$entry" | awk '{print $NF}')
            
            if [[ "$filename" == */ ]]; then
                _log_debug "Single entry is directory, not tar format"
                return 1
            fi
            
            _log_debug "Single file detected, checking tar magic numbers"
            return $(_check_tar_magic "$archive")
        fi
        
        return 1
    }
    
    _check_tar_magic() {
        local archive="$1"
        
        local header
        if [[ -n "${inner_config[password]}" ]]; then
            header=$(_execute_7z_with_password "x" "-so" "$archive" 2>/dev/null | head -c 512)
        else
            header=$("${inner_commands[sevenz]}" "x" "-so" "$archive" 2>/dev/null | head -c 512)
        fi
        
        [[ -z "$header" ]] && return 1
        
        local magic
        magic=$(echo -n "$header" | dd bs=1 skip=257 count=5 2>/dev/null)
        if [[ "$magic" == "ustar" ]]; then
            _log_debug "POSIX tar magic detected"
            return 0
        fi
        
        magic=$(echo -n "$header" | dd bs=1 skip=257 count=8 2>/dev/null)
        if [[ "$magic" == "ustar  " || "$magic" == "ustar 00" ]]; then
            _log_debug "GNU tar magic detected"
            return 0
        fi
        
        _log_debug "No tar magic found"
        return 1
    }
    
    
    _split_args() {
        local args_string="$1"
        [[ -n "$args_string" ]] && echo ${=args_string} || echo ""
    }
    
    _build_7z_args() {
        local -a result_args=("$@")
        
        if [[ "$1" == "a" && -n "${inner_config[password]}" ]]; then
            result_args+=("-mhe=on")
        fi
        
        if [[ "$1" == "a" && -n "${inner_config[exclude_patterns]}" ]]; then
            local -a excludes=($(_split_args "${inner_config[exclude_patterns]}"))
            for pattern in "${excludes[@]}"; do
                result_args+=("-xr!$pattern")
            done
        fi
        
        if [[ -n "${inner_config[extra_7z_args]}" ]]; then
            local -a extras=($(_split_args "${inner_config[extra_7z_args]}"))
            result_args+=("${extras[@]}")
        fi
        
        _7z_args=("${result_args[@]}")
    }
    
    _build_tar_args() {
        local operation="$1"
        local option="$2"
        local -a args=()
        
        if [[ "$operation" == "c" && -n "${inner_config[exclude_patterns]}" ]]; then
            local -a excludes=($(_split_args "${inner_config[exclude_patterns]}"))
            for pattern in "${excludes[@]}"; do
                args+=("--exclude=$pattern")
            done
        fi
        
        if [[ -n "${inner_config[extra_tar_args]}" ]]; then
            local -a extras=($(_split_args "${inner_config[extra_tar_args]}"))
            args+=("${extras[@]}")
        fi
        
        args+=("-${operation}${option}")
        printf '%s\n' "${args[@]}"
    }
    
    _execute_7z_command() {
        local -a cmd_args=("$@")
        
        if [[ -n "${inner_config[password]}" ]]; then
            _execute_7z_with_password "${cmd_args[@]}"
        else
            _log_debug "7z command: ${inner_commands[sevenz]} ${cmd_args[*]}"
            "${inner_commands[sevenz]}" "${cmd_args[@]}"
        fi
    }
    
    _execute_7z_with_password() {
        local -a cmd_args=("$@")
        
        _log_debug "7z command: ${inner_commands[sevenz]} ${cmd_args[*]} [with password]"
        "${inner_commands[sevenz]}" "${cmd_args[@]}" "-p${inner_config[password]}"
        local exit_code=$?
        
        return $exit_code
    }
    
    
    _generate_password_if_needed() {
        if [[ "${inner_config[gen_pass]}" != true ]]; then
            return 0
        fi
        
        if ! _command_exists "gen_pass"; then
            _handle_error 1 "gen_pass command not found" "Install gen_pass"
            return 1
        fi
        
        local input_file=""
        case "${inner_config[action]}" in
            "compress")
                input_file=$(basename "${inner_config[target]}")
                ;;
            "extract"|"list"|"info")
                input_file=$(basename "${inner_config[source]}")
                ;;
            *)
                _handle_error 1 "Invalid action for password generation: ${inner_config[action]}"
                return 1
                ;;
        esac
        
        _log_debug "Generating password for: $input_file"
        local gen_output
        if gen_output=$(gen_pass -i "$input_file" 2>&1); then
            inner_config[password]="$gen_output"
            _log_debug "Password generated (length: ${#inner_config[password]})"
        else
            _handle_error 1 "Failed to generate password" "$gen_output"
            return 1
        fi
        
        return 0
    }
    
    _validate_password_options() {
        if [[ -n "${inner_config[password]}" && "${inner_config[gen_pass]}" == true ]]; then
            _handle_error 1 "Cannot use both manual password and --gen-pass"
            return 1
        fi
        
        if [[ -n "${inner_config[password]}" ]]; then
            local len=${#inner_config[password]}
            if [[ $len -lt 4 ]]; then
                _log_warning "Password is very short ($len characters)"
            fi
        fi
        
        return 0
    }

    
    _compress_with_tar() {
        local src="$1" tgt="$2"
        _log_info "Compressing with tar+7z: $src -> $tgt"
        
        local -a src_files
        while IFS= read -r line; do
            src_files+=("$line")
        done < <(_safe_split_paths "$src")
        
        _build_7z_args "a" "-t7z" "-si" "$tgt"
        local -a sevenz_args=("${_7z_args[@]}")
        local -a tar_args=($(_build_tar_args "c" "f"))
        
        _log_debug "Command: ${inner_commands[tar]} ${tar_args[*]} - ${src_files[*]} | ${inner_commands[sevenz]} ${sevenz_args[*]}"
        
        if ! "${inner_commands[tar]}" "${tar_args[@]}" - "${src_files[@]}" 2>/dev/null | _execute_7z_command "${sevenz_args[@]}"; then
            _handle_error 1 "Tar+7z compression failed"
            [[ -f "$tgt" && ! -s "$tgt" ]] && rm -f "$tgt"
            return 1
        fi
        
        if [[ ! -s "$tgt" ]]; then
            _handle_error 1 "Output file is empty: $tgt"
            return 1
        fi
        
        _log_ok "Compression completed: $tgt ($(_format_size $(_get_file_size "$tgt")))"
        return 0
    }
    
    _compress_direct() {
        local src="$1" tgt="$2"
        _log_info "Direct 7z compression: $src -> $tgt"
        
        local -a src_files
        while IFS= read -r line; do
            src_files+=("$line")
        done < <(_safe_split_paths "$src")
        
        _build_7z_args "a" "-t7z" "$tgt" "${src_files[@]}"
        local -a sevenz_args=("${_7z_args[@]}")
        
        _log_debug "Command: ${inner_commands[sevenz]} ${sevenz_args[*]}"
        
        if ! _execute_7z_command "${sevenz_args[@]}"; then
            _handle_error 1 "Direct 7z compression failed"
            [[ -f "$tgt" && ! -s "$tgt" ]] && rm -f "$tgt"
            return 1
        fi
        
        if [[ -f "$tgt" && -s "$tgt" ]]; then
            _log_ok "Compression completed: $tgt ($(_format_size $(_get_file_size "$tgt")))"
        elif [[ -f "${tgt}.001" ]]; then
            local total_size=0
            local volume_count=0
            for vol in "${tgt}".???; do
                if [[ -f "$vol" ]]; then
                    ((volume_count++))
                    total_size=$((total_size + $(_get_file_size "$vol")))
                fi
            done
            _log_ok "Compression completed: $tgt ($volume_count volumes, $(_format_size $total_size) total)"
        else
            _handle_error 1 "Output file is empty or missing: $tgt"
            return 1
        fi
        return 0
    }
    
    _extract_with_tar() {
        local src="$1" tgt="$2"
        _log_info "Extracting with tar+7z: $src -> $tgt"
        
        local temp_tar
        temp_tar=$(mktemp "/tmp/7zx_temp_XXXXXX") || {
            _handle_error 1 "Failed to create temporary file"
            return 1
        }
        mv "$temp_tar" "$temp_tar.tar" || {
            _handle_error 1 "Failed to rename temporary file"
            return 1
        }
        temp_tar="$temp_tar.tar"
        _register_cleanup "$temp_tar"
        
        _build_7z_args "x" "-so" "$src"
        local -a sevenz_args=("${_7z_args[@]}")
        if ! _execute_7z_command "${sevenz_args[@]}" > "$temp_tar"; then
            _handle_error 1 "7z extraction failed"
            return 1
        fi
        
        if [[ ! -s "$temp_tar" ]]; then
            _handle_error 1 "Extracted tar is empty"
            return 1
        fi
        
        local -a tar_args=($(_build_tar_args "x" "f"))
        if ! "${inner_commands[tar]}" "${tar_args[@]}" "$temp_tar" -C "$tgt" 2>/dev/null; then
            _handle_error 1 "Tar extraction failed"
            return 1
        fi
        
        _log_ok "Extraction completed to: $tgt"
        return 0
    }
    
    _extract_direct() {
        local src="$1" tgt="$2"
        _log_info "Direct 7z extraction: $src -> $tgt"
        
        _build_7z_args "x" "-o$tgt" "$src"
        local -a sevenz_args=("${_7z_args[@]}")
        
        if ! _execute_7z_command "${sevenz_args[@]}"; then
            _handle_error 1 "Direct 7z extraction failed"
            return 1
        fi
        
        if [[ ! -d "$tgt" ]] || [[ -z "$(ls -A "$tgt" 2>/dev/null)" ]]; then
            _handle_error 1 "Target directory is empty after extraction"
            return 1
        fi
        
        _log_ok "Extraction completed to: $tgt"
        return 0
    }
    
    _list_tar_archive() {
        local src="$1"
        _build_7z_args "x" "-so" "$src"
        local -a sevenz_args=("${_7z_args[@]}")
        local -a tar_args=($(_build_tar_args "t" "f"))
        
        _execute_7z_command "${sevenz_args[@]}" | "${inner_commands[tar]}" "${tar_args[@]}" -
    }
    
    _list_direct_archive() {
        local src="$1"
        _build_7z_args "l" "$src"
        local -a sevenz_args=("${_7z_args[@]}")
        
        _execute_7z_command "${sevenz_args[@]}"
    }
    
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--compress)
                if [[ $# -lt 3 || -z "$2" || -z "$3" || "$2" == -* || "$3" == -* ]]; then
                    _handle_error 1 "compress requires SOURCE and TARGET arguments"
                    return 1
                fi
                inner_config[action]="compress"
                inner_config[source]="$2"
                inner_config[target]="$3"
                shift 3
                ;;
            -x|--extract)
                if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                    _handle_error 1 "extract requires SOURCE argument"
                    return 1
                fi
                inner_config[action]="extract"
                inner_config[source]="$2"
                if [[ -n "$3" && "$3" != -* ]]; then
                    inner_config[target]="$3"
                    shift 3
                else
                    inner_config[target]="."
                    shift 2
                fi
                ;;
            -l|--list)
                if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                    _handle_error 1 "list requires ARCHIVE argument"
                    return 1
                fi
                inner_config[action]="list"
                inner_config[source]="$2"
                shift 2
                ;;
            -i|--info)
                if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                    _handle_error 1 "info requires ARCHIVE argument"
                    return 1
                fi
                inner_config[action]="info"
                inner_config[source]="$2"
                shift 2
                ;;
            -p|--password)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    _handle_error 1 "password option requires PASSWORD argument"
                    return 1
                fi
                inner_config[password]="$2"
                shift 2
                ;;
            --7z-args)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    _handle_error 1 "7z-args option requires ARGS argument"
                    return 1
                fi
                inner_config[extra_7z_args]="$2"
                shift 2
                ;;
            --tar-args)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    _handle_error 1 "tar-args option requires ARGS argument"
                    return 1
                fi
                inner_config[extra_tar_args]="$2"
                shift 2
                ;;
            -v|--verbose)
                inner_config[verbose]=true
                shift
                ;;
            --no-tar)
                if [[ "${inner_config[force_tar]}" == true ]]; then
                    _handle_error 1 "Cannot use --no-tar and --force-tar together"
                    return 1
                fi
                inner_config[use_tar]=false
                shift
                ;;
            --force-tar)
                if [[ "${inner_config[use_tar]}" == false ]]; then
                    _handle_error 1 "Cannot use --no-tar and --force-tar together"
                    return 1
                fi
                inner_config[force_tar]=true
                inner_config[use_tar]=true
                shift
                ;;
            --exclude)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    _handle_error 1 "exclude option requires PATTERN argument"
                    return 1
                fi
                inner_config[exclude_patterns]="${inner_config[exclude_patterns]} $2"
                shift 2
                ;;
            --gen-pass)
                inner_config[gen_pass]=true
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
  --7z-args "ARGS"              Pass arguments specifically to 7z command
  --tar-args "ARGS"             Pass arguments specifically to tar command
  -v, --verbose                 Enable verbose output
  --no-tar                      Force direct 7z compression (no tar packing)
  --force-tar                   Force tar packing (compression and extraction)
  --exclude "PATTERN"           Exclude files matching pattern (supports multiple)
  --gen-pass                    Auto-generate password from target filename (basename)
  -h, --help                    Show this help message

TAR PACKING BEHAVIOR:
  Default: Single files use direct 7z, multiple files/directories use tar+7z
  --no-tar: Always use direct 7z compression
  --force-tar: Always use tar+7z compression

EXAMPLES:
  7zx -c /root backup.7z -p "mypassword"
  7zx -c /root backup.7z --no-tar -p "mypassword"
  7zx -c /root backup.7z --gen-pass
  7zx -c /root backup.7z --exclude "*.log" --exclude "*.tmp"
  7zx -c /root backup.7z --7z-args "-v100m -mx=0"
  7zx -c "file1.txt file2.txt" backup.7z
  7zx -c "file\ with\ spaces.txt" backup.7z
  7zx -c "file1.txt file\ with\ spaces.txt dir/" backup.7z
  7zx -x backup.7z /tmp/restore -p "mypassword"
  7zx -x backup.7z --gen-pass
  7zx -x backup.7z --force-tar
  7zx -l backup.7z
  7zx -i backup.7z -p "mypassword"
EOF
                return 0
                ;;
            *)
                _handle_error 1 "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    
    _setup_cleanup
    
    if [[ -z "${inner_config[action]}" ]]; then
        _handle_error 1 "No action specified" "Use -h for help"
        return 1
    fi
    
    case "${inner_config[action]}" in
        "compress")
            if [[ -z "${inner_config[source]}" || -z "${inner_config[target]}" ]]; then
                _handle_error 1 "compress requires SOURCE and TARGET"
                return 1
            fi
            ;;
        "extract"|"list"|"info")
            if [[ -z "${inner_config[source]}" ]]; then
                _handle_error 1 "${inner_config[action]} requires SOURCE"
                return 1
            fi
            ;;
    esac
    
    _validate_password_options || return 1
    
    _initialize_commands || return 1
    
    _generate_password_if_needed || return 1
    
    case "${inner_config[action]}" in
        "compress")
            _validate_source_path "${inner_config[source]}" || return 1
            _validate_target_directory "${inner_config[target]}" || return 1
            ;;
        "extract")
            _validate_source_file "${inner_config[source]}" || return 1
            _validate_extract_target "${inner_config[target]}" || return 1
            ;;
        "list"|"info")
            _validate_source_file "${inner_config[source]}" || return 1
            ;;
    esac
    
    case "${inner_config[action]}" in
        "compress")
            if _should_use_tar_for_compression "${inner_config[source]}"; then
                _compress_with_tar "${inner_config[source]}" "${inner_config[target]}"
            else
                _compress_direct "${inner_config[source]}" "${inner_config[target]}"
            fi
            ;;
        "extract")
            if _is_tar_archive "${inner_config[source]}"; then
                _log_info "Detected tar-packed archive"
                _extract_with_tar "${inner_config[source]}" "${inner_config[target]}"
            else
                _log_info "Detected direct 7z archive"
                _extract_direct "${inner_config[source]}" "${inner_config[target]}"
            fi
            ;;
        "list")
            if _is_tar_archive "${inner_config[source]}"; then
                _list_tar_archive "${inner_config[source]}"
            else
                _list_direct_archive "${inner_config[source]}"
            fi
            ;;
        "info")
            _build_7z_args "l" "${inner_config[source]}"
            local -a args=("${_7z_args[@]}")
            _log_info "Archive information for ${inner_config[source]}"
            _execute_7z_command "${args[@]}"
            ;;
        *)
            _handle_error 1 "Unknown action: ${inner_config[action]}"
            return 1
            ;;
    esac
}
