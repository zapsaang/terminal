gen_pass() {
  local input=""
  local length=64
  local level="medium"

  _gen_pass_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
      shasum -a 256 | awk '{print $1}'
    else
      echo "Error: No SHA-256 utility found (install coreutils or use macOS shasum)" >&2
      return 1
    fi
  }

  while [[ $# -gt 0 ]]; do
    case $1 in
      -i|--input)
        if [[ $# -lt 2 ]] || [[ -z "$2" ]]; then
          echo "Error: --input requires a value" >&2
          return 1
        fi
        input="$2"
        shift 2
        ;;
      -l|--length)
        if [[ $# -lt 2 ]] || [[ -z "$2" ]]; then
          echo "Error: --length requires a value" >&2
          return 1
        fi
        length="$2"
        shift 2
        ;;
      -L|--level)
        if [[ $# -lt 2 ]] || [[ -z "$2" ]]; then
          echo "Error: --level requires a value" >&2
          return 1
        fi
        level="$2"
        shift 2
        ;;
      -h|--help)
        cat <<EOF
Usage: gen_pass [OPTIONS]
Generate a deterministic password based on input seed and security level

Options:
  -i, --input TEXT    Input seed (required, max 1000 chars)
  -l, --length NUM    Password length (default: 64, max 4096)
  -L, --level LEVEL   Security level: low|medium|strong (default: medium)
  -h, --help          Show this help message

Security Levels:
  low     - lowercase letters only (a-z)
  medium  - letters + numbers (A-Z, a-z, 0-9)
  strong  - letters + numbers + symbols

Examples:
  gen_pass -i "myservice" -l 16 -L strong
  gen_pass --input "example.com" --length 32 --level medium
EOF
        return 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        echo "Use -h or --help for usage information" >&2
        return 1
        ;;
    esac
  done

  if [ -z "$input" ]; then
    echo "Error: input is required (-i or --input)" >&2
    return 1
  fi

  if [ ${#input} -gt 1000 ]; then
    echo "Error: input too long (maximum 1000 characters)" >&2
    return 1
  fi

  if ! [[ "$length" =~ ^[0-9]+$ ]] || [ "$length" -le 0 ]; then
    echo "Error: length must be a positive integer" >&2
    return 1
  fi

  if [ "$length" -gt 4096 ]; then
    echo "Error: length too large (maximum 4096)" >&2
    return 1
  fi

  case "$level" in
    low|medium|strong) ;;
    *)
      echo "Error: level must be low, medium, or strong" >&2
      return 1
      ;;
  esac

  local charset=""
  local specials='!@#%^&*()_=+[]{}:,.?-'

  case "$level" in
    low) charset='abcdefghijklmnopqrstuvwxyz' ;;
    medium) charset='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' ;;
    strong) charset="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789${specials}" ;;
  esac

  local charset_length=${#charset}
  local password=""
  local counter=0

  while [ ${#password} -lt $length ]; do
    local seed="${input}${counter}"
    local hash=$(printf "%s" "$seed" | _gen_pass_sha256)
    
    # 检查哈希计算是否成功
    if [ -z "$hash" ] || [ ${#hash} -ne 64 ]; then
      echo "Error: Hash calculation failed" >&2
      return 1
    fi
    
    local i=0
    while [ $i -lt ${#hash} ] && [ ${#password} -lt $length ]; do
      local hex_chunk="${hash:$i:2}"
      local value=$((0x$hex_chunk))
      local char_index=$((value % charset_length))
      password+="${charset:$char_index:1}"
      i=$((i+2))
    done
    counter=$((counter+1))
  done

  password="${password:0:$length}"

  local type_hash=$(printf "%s" "$input" | _gen_pass_sha256)
  
  if [ -z "$type_hash" ] || [ ${#type_hash} -ne 64 ]; then
    echo "Error: Type hash calculation failed" >&2
    return 1
  fi

  replace_char_at_pos() {
    local str="$1" pos="$2" char="$3"
    local len=${#str}
    
    if [ "$len" -eq 0 ]; then
      echo "$char"
      return
    fi
    
    pos=$((pos % len))
    echo "${str:0:$pos}${char}${str:$((pos+1))}"
  }

  if [ "$level" != "low" ]; then
    if ! [[ "$password" =~ [A-Z] ]]; then
      local pos=$((0x${type_hash:0:2} % length))
      local idx=$((0x${type_hash:2:2} % 26))
      local new_char="${charset:$idx:1}" 
      password=$(replace_char_at_pos "$password" $pos "$new_char")
    fi
    
    if ! [[ "$password" =~ [a-z] ]]; then
      local pos=$((0x${type_hash:4:2} % length))
      local idx=$((0x${type_hash:6:2} % 26))
      local new_char="${charset:$((idx+26)):1}" 
      password=$(replace_char_at_pos "$password" $pos "$new_char")
    fi
    
    if ! [[ "$password" =~ [0-9] ]]; then
      local pos=$((0x${type_hash:8:2} % length))
      local digit=$((0x${type_hash:10:2} % 10))
      password=$(replace_char_at_pos "$password" $pos "$digit")
    fi
  fi

  if [ "$level" = "strong" ]; then
    if ! [[ "$password" =~ [$specials] ]]; then
      local pos=$((0x${type_hash:12:2} % length))
      local idx=$((0x${type_hash:14:2} % ${#specials}))
      local new_char="${specials:$idx:1}"
      password=$(replace_char_at_pos "$password" $pos "$new_char")
    fi
  fi

  echo "$password"
}
