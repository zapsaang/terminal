gen_pass() {
  local input=""
  local length=64
  local level="medium"
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      -i|--input)
        input="$2"
        shift 2
        ;;
      -l|--length)
        length="$2"
        shift 2
        ;;
      -L|--level)
        level="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: gen_pass [OPTIONS]"
        echo "Generate a password based on input and security level"
        echo ""
        echo "Options:"
        echo "  -i, --input TEXT    Input seed (required)"
        echo "  -l, --length NUM    Password length (default: 64)"
        echo "  -L, --level LEVEL   Security level: low|medium|strong (default: medium)"
        echo "  -h, --help          Show this help message"
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
    echo "Use -h or --help for usage information" >&2
    return 1
  fi

  if ! [[ "$length" =~ ^[0-9]+$ ]] || [ "$length" -le 0 ]; then
    echo "Error: length must be a positive integer" >&2
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
    low) charset=$(printf "%s" {a..z}) ;;
    medium) charset=$(printf "%s%s%s" {A..Z} {a..z} {0..9}) ;;
    strong) charset=$(printf "%s%s%s%s" {A..Z} {a..z} {0..9} "$specials") ;;
    *) echo "Invalid level: choose low, medium, or strong" >&2; return 1 ;;
  esac

  local charset_length=${#charset}
  local password=""

  local counter=0
  
  while [ ${#password} -lt $length ]; do
    local seed="${input}${counter}"
    local hash=$(printf "%s" "$seed" | sha256sum | awk '{print $1}')
    
    local i=0
    while [ $i -lt 64 ] && [ ${#password} -lt $length ]; do
      local hex_chunk="${hash:$i:2}"
      local value=$((0x$hex_chunk))
      local char_index=$((value % charset_length))
      local char="${charset:$char_index:1}"
      password="${password}${char}"
      i=$((i + 2))
    done
    
    counter=$((counter + 1))
  done

  password="${password:0:$length}"
  
  local type_hash=$(printf "%s" "$input" | sha1sum | awk '{print $1}')

  replace_char_at_pos() {
    local str="$1"
    local pos="$2"
    local char="$3"
    local len=${#str}
    
    pos=$((pos % len))
    if [ $pos -lt 0 ]; then
      pos=0
    fi
    
    echo "${str:0:$pos}${char}${str:$((pos+1))}"
  }

  if [ "$level" != "low" ]; then
    if ! printf "%s" "$password" | grep -q '[A-Z]' 2>/dev/null; then
      local pos=$((0x${type_hash:0:2} % length))
      local char_idx=$((0x${type_hash:2:2} % 26))
      local new_char=$(printf "%s" {A..Z} | cut -c$((char_idx + 1)))
      password=$(replace_char_at_pos "$password" $pos "$new_char")
    fi
    
    if ! printf "%s" "$password" | grep -q '[a-z]' 2>/dev/null; then
      local pos=$((0x${type_hash:4:2} % length))
      local char_idx=$((0x${type_hash:6:2} % 26))
      local new_char=$(printf "%s" {a..z} | cut -c$((char_idx + 1)))
      password=$(replace_char_at_pos "$password" $pos "$new_char")
    fi

    if ! printf "%s" "$password" | grep -q '[0-9]' 2>/dev/null; then
      local pos=$((0x${type_hash:8:2} % length))
      local digit=$((0x${type_hash:10:2} % 10))
      password=$(replace_char_at_pos "$password" $pos "$digit")
    fi
  fi

  if [ "$level" = "strong" ]; then
    if ! printf "%s" "$password" | grep -q "[$specials]" 2>/dev/null; then
      local pos=$((0x${type_hash:12:2} % length))
      local spec_idx=$((0x${type_hash:14:2} % ${#specials}))
      local new_char="${specials:$spec_idx:1}"
      password=$(replace_char_at_pos "$password" $pos "$new_char")
    fi
  fi

  echo "$password"
}
